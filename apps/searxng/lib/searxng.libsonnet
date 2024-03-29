local defaults = {
  name:: "please provide deployment name, \"opensearch-dashboard\" is suggested",
  namespace:: error 'pelase provide namespace',
  version:: error "please provide version",
  subdomain:: error "please provide subdomain name",
  domain:: error "please provide domainname",
  fqdn:: "%s.%s" % [self.subdomain, self.domain],
  replicas:: error 'please provide replicas for the deployment'
};

function(params) {
  local ne = self,
  _config:: defaults + params,

  serviceaccount: {
    kind: "ServiceAccount",
    apiVersion: "v1",
    metadata: {
      name: ne._config.name,
      namespace: ne._config.namespace
    }
  },

  ingress: {
    kind: "Ingress",
    apiVersion: "networking.k8s.io/v1",
    metadata: {
      name: ne._config.name,
      namespace: ne._config.namespace,
      annotations: {
        "cert-manager.io/cluster-issuer": "letsencrypt-prod",
        "external-dns.alpha.kubernetes.io/hostname": ne._config.fqdn
      }
    },
    spec: {
      ingressClassName: "nginx",
      tls: [
        {
          hosts: [
            ne._config.fqdn
          ],
          secretName: std.strReplace(ne._config.fqdn, ".", "-") + "-cert"
        }
      ],
      rules: [
        {
          host: ne._config.fqdn,
          http: {
            paths: [
              {
                path: "/",
                pathType: "Prefix",
                backend: {
                  service: {
                    name: ne._config.name,
                    port: { number: 80 }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  },

  service: {
    kind: "Service",
    apiVersion: "v1",
    metadata: {
      name: ne._config.name,
      namespace: ne._config.namespace
    },
    spec: {
      selector: { app: ne._config.name },
      ports: [
        {
          port: 80,
          targetPort: 8080   
        }
      ]
    }
  },

  deployment: {
    kind: "Deployment",
    apiVersion: "apps/v1",
    metadata: {
      name: ne._config.name,
      namespace: ne._config.namespace
    },
    spec: {
      replicas: ne._config.replicas,
      selector: { matchLabels: { app: ne._config.name }},
      template: {
        metadata: {
          name: ne._config.name,
          labels: { app: ne._config.name },
          annotations: {
            "vault.hashicorp.com/agent-inject": "true",
            "vault.hashicorp.com/role": "searxng",
            "vault.hashicorp.com/agent-inject-secret-secret": "kv/searxng",
            "vault.hashicorp.com/agent-inject-template-secret": |||
              {{- with secret "kv/searxng" -}}
              {{ .Data.data.secret }}
              {{- end -}}
            |||
          }
        },
        spec: {
          hostUsers: false,
          serviceAccountName: ne._config.name,
          containers: [
            {
              name: ne._config.name,
              image: "docker.io/searxng/searxng:" + ne._config.version,
              ports: [
                {
                  containerPort: 8080
                }
              ],
              command: [
                "/bin/sh",
                "-c"
              ],
              args: [
                "export SEARXNG_SECRET=$(cat /vault/secrets/secret) && /sbin/tini -- /usr/local/searxng/dockerfiles/docker-entrypoint.sh"
              ],
              env: [
                {
                  name: "SEARXNG_BASE_URL",
                  value: "https://%s/" % ne._config.fqdn
                }
              ],
              volumeMounts: [
                {
                  mountPath: "/etc/searxng",
                  name: "config"
                }
              ],
              resources: {
                limits: { cpu: "250m", memory: "512Mi" },
                requests: { cpu: "100m", memory: "256Mi" }
              }
            }
          ],
          volumes: [
            {
              name: "config",
              configMap: {
                name: ne._config.name
              }
            }
          ],
          dnsConfig: {
            options: [
              {
                name: "ndots",
                value: "1"
              }
            ]
          }
        }
      }
    }
  },

  "service-redis": {
    kind: "Service",
    apiVersion: "v1",
    metadata: {
      name: "redis",
      namespace: ne._config.namespace
    },
    spec: {
      selector: { app: "redis" },
      ports: [
        {
          port: 6379,
          targetPort: "redis"
        }
      ]
    }
  },

  "deployment-redis": {
    kind: "Deployment",
    apiVersion: "apps/v1",
    metadata: {
      name: "redis",
      namespace: ne._config.namespace
    },
    spec: {
      replicas: 1,
      selector: { matchLabels: { app: "redis" }},
      template: {
        metadata: {
          name: "redis",
          labels: { app: "redis" },
        },
        spec: {
          hostUsers: false,
          containers: [
            {
              name: "redis",
              image: "redis:alpine",
              ports: [
                {
                  name: "redis",
                  containerPort: 6379
                }
              ],
              command: [
                "redis-server",
                "--save",
                "",
                "--appendonly",
                "no"
              ],
              resources: {
                limits: { cpu: "100m", memory: "128Mi" }
              }
            }
          ]
        }
      }
    }
  },

  configmap: {
    kind: "ConfigMap",
    apiVersion: "v1",
    metadata: {
      name: ne._config.name,
      namespace: ne._config.namespace
    },
    data: {
      "settings.yml": |||
        general:
          # Debug mode, only for development
          debug: false
          # displayed name
          instance_name: "SearXNG"
          # For example: https://example.com/privacy
          privacypolicy_url: false
          # use true to use your own donation page written in searx/info/en/donate.md
          # use false to disable the donation link
          donation_url: https://docs.searxng.org/donate.html
          # mailto:contact@example.com
          contact_url: false
          # record stats
          enable_metrics: true

        brand:
          new_issue_url: https://github.com/searxng/searxng/issues/new
          docs_url: https://docs.searxng.org/
          public_instances: https://searx.space
          wiki_url: https://github.com/searxng/searxng/wiki
          issue_url: https://github.com/searxng/searxng/issues

        search:
          safe_search: 0
          autocomplete: "duckduckgo"
          autocomplete_min: 2
          default_lang: "auto"
          ban_time_on_fail: 5
          max_ban_time_on_fail: 120
          formats:
            - html
            - json
            - rss
          suspended_times:
            SearxEngineAccessDenied: 86400
            SearxEngineCaptcha: 86400
            SearxEngineTooManyRequests: 3600
            cf_SearxEngineCaptcha: 1296000
            cf_SearxEngineAccessDenied: 86400
            recaptcha_SearxEngineCaptcha: 604800

        server:
          port: 8888
          bind_address: "127.0.0.1"
          base_url: false
          limiter: true

          secret_key: "ultrasecretkey" # Is overwritten by ${SEARXNG_SECRET}
          image_proxy: true
          http_protocol_version: "1.1"
          method: "GET"
          default_http_headers:
            X-Content-Type-Options: nosniff
            X-XSS-Protection: 1; mode=block
            X-Download-Options: noopen
            X-Robots-Tag: noindex, nofollow
            Referrer-Policy: no-referrer

        redis:
          url: "redis://@redis.searxng.svc.cluster.local:6379/0"

        ui:
          static_path: ""
          static_use_hash: false
          templates_path: ""
          query_in_title: true
          infinite_scroll: true
          default_theme: simple
          center_alignment: false
          default_locale: ""
          results_on_new_tab: false
          theme_args:
            simple_style: auto

        outgoing:
          request_timeout: 3.0
          # max_request_timeout: 10.0
          useragent_suffix: ""
          pool_connections: 100
          pool_maxsize: 20
          enable_http2: true

        enabled_plugins:
        #   # these plugins are enabled if nothing is configured ..
        #   - 'Hash plugin'
        #   - 'Search on category select'
        #   - 'Self Information'
          - 'Tracker URL remover'
        #   - 'Ahmia blacklist'  # activation depends on outgoing.using_tor_proxy
        #   # these plugins are disabled if nothing is configured ..
          - 'Hostname replace'  # see hostname_replace configuration below
        #   - 'Open Access DOI rewrite'
          - 'Vim-like hotkeys'
        #   - 'Tor check plugin'
        #   # Read the docs before activate: auto-detection of the language could be
        #   # detrimental to users expectations / users can activate the plugin in the
        #   # preferences if they want.
        #   - 'Autodetect search language'

        # Configuration of the "Hostname replace" plugin:
        #
        hostname_replace:
          '.*\.pinterest\..+$': false
          '.*\.quora\.com$': false
          '.*\.alternativeto\.net$': false
          '.*\.geeksforgeeks\.org$': false
        #   '(.*\.)?youtube\.com$': 'invidious.example.com'
        #   '(.*\.)?youtu\.be$': 'invidious.example.com'
        #   '(.*\.)?youtube-noocookie\.com$': 'yotter.example.com'
        # '(.*\.)?reddit\.com$': 'teddit.example.se'
        # '(.*\.)?redd\.it$': 'teddit.example.se'
        #   '(www\.)?twitter\.com$': 'nitter.example.com'
        #   # to remove matching host names from result list, set value to false
        #   'spam\.example\.com': false

        checker:
          # disable checker when in debug mode
          off_when_debug: true

          # use "scheduling: false" to disable scheduling
          # scheduling: interval or int

          # to activate the scheduler:
          # * uncomment "scheduling" section
          # * add "cache2 = name=searxngcache,items=2000,blocks=2000,blocksize=4096,bitmap=1"
          #   to your uwsgi.ini

          # scheduling:
          #   start_after: [300, 1800]  # delay to start the first run of the checker
          #   every: [86400, 90000]     # how often the checker runs

          # additional tests: only for the YAML anchors (see the engines section)
          #
          additional_tests:
            rosebud: &test_rosebud
              matrix:
                query: rosebud
                lang: en
              result_container:
                - not_empty
                - ['one_title_contains', 'citizen kane']
              test:
                - unique_results

            android: &test_android
              matrix:
                query: ['android']
                lang: ['en', 'de', 'fr', 'zh-CN']
              result_container:
                - not_empty
                - ['one_title_contains', 'google']
              test:
                - unique_results

          # tests: only for the YAML anchors (see the engines section)
          tests:
            infobox: &tests_infobox
              infobox:
                matrix:
                  query: ["linux", "new york", "bbc"]
                result_container:
                  - has_infobox

        categories_as_tabs:
          general:
          images:
          videos:
          news:
          # map:
          music:
          it:
          science:
          files:
          # social media:

        engines:
          - name: apk mirror
            engine: apkmirror
            timeout: 4.0
            shortcut: apkm

          # Requires Tor
          - name: ahmia
            engine: ahmia
            categories: onions
            enable_http: true
            shortcut: ah

          - name: arch linux wiki
            engine: archlinux
            shortcut: al

          - name: archive is
            engine: xpath
            search_url: https://archive.is/search/?q={query}
            url_xpath: (//div[@class="TEXT-BLOCK"]/a)/@href
            title_xpath: (//div[@class="TEXT-BLOCK"]/a)
            content_xpath: //div[@class="TEXT-BLOCK"]/ul/li
            categories: general
            timeout: 7.0
            disabled: true
            shortcut: ai
            soft_max_redirects: 1
            about:
              website: https://archive.is/
              wikidata_id: Q13515725
              official_api_documentation: https://mementoweb.org/depot/native/archiveis/
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: artic
            engine: artic
            shortcut: arc
            timeout: 4.0

          - name: arxiv
            engine: arxiv
            shortcut: arx
            timeout: 4.0

          - name: bandcamp
            engine: bandcamp
            shortcut: bc
            categories: music

          - name: wikipedia
            engine: wikipedia
            shortcut: wp
            base_url: 'https://{language}.wikipedia.org/'

          - name: btdigg
            engine: btdigg
            shortcut: bt

          - name: ccc-tv
            engine: xpath
            paging: false
            search_url: https://media.ccc.de/search/?q={query}
            url_xpath: //div[@class="caption"]/h3/a/@href
            title_xpath: //div[@class="caption"]/h3/a/text()
            content_xpath: //div[@class="caption"]/h4/@title
            categories: videos
            disabled: true
            shortcut: c3tv
            about:
              website: https://media.ccc.de/
              wikidata_id: Q80729951
              official_api_documentation: https://github.com/voc/voctoweb
              use_official_api: false
              require_api_key: false
              results: HTML
              # We don't set language: de here because media.ccc.de is not just
              # for a German audience. It contains many English videos and many
              # German videos have English subtitles.

          - name: openverse
            engine: openverse
            categories: images
            shortcut: opv

          - name: crossref
            engine: crossref
            shortcut: cr
            timeout: 30
            disabled: true

          - name: yep
            engine: json_engine
            shortcut: yep
            categories: general
            disabled: true
            paging: false
            content_html_to_text: true
            title_html_to_text: true
            search_url: https://api.yep.com/fs/1/?type=web&q={query}&no_correct=false&limit=100
            results_query: 1/results
            title_query: title
            url_query: url
            content_query: snippet
            about:
              website: https://yep.com
              use_official_api: false
              require_api_key: false
              results: JSON

          - name: curlie
            engine: xpath
            shortcut: cl
            categories: general
            disabled: true
            paging: true
            lang_all: ''
            search_url: https://curlie.org/search?q={query}&lang={lang}&start={pageno}&stime=92452189
            page_size: 20
            results_xpath: //div[@id="site-list-content"]/div[@class="site-item"]
            url_xpath: ./div[@class="title-and-desc"]/a/@href
            title_xpath: ./div[@class="title-and-desc"]/a/div
            content_xpath: ./div[@class="title-and-desc"]/div[@class="site-descr"]
            about:
              website: https://curlie.org/
              wikidata_id: Q60715723
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: currency
            engine: currency_convert
            categories: general
            shortcut: cc

          - name: deezer
            engine: deezer
            shortcut: dz
            disabled: true

          - name: deviantart
            engine: deviantart
            shortcut: da
            timeout: 3.0

          - name: ddg definitions
            engine: duckduckgo_definitions
            shortcut: ddd
            weight: 2
            disabled: true
            tests: *tests_infobox

          - name: docker hub
            engine: docker_hub
            shortcut: dh
            categories: [it, packages]

          - name: erowid
            engine: xpath
            paging: true
            first_page_num: 0
            page_size: 30
            search_url: https://www.erowid.org/search.php?q={query}&s={pageno}
            url_xpath: //dl[@class="results-list"]/dt[@class="result-title"]/a/@href
            title_xpath: //dl[@class="results-list"]/dt[@class="result-title"]/a/text()
            content_xpath: //dl[@class="results-list"]/dd[@class="result-details"]
            categories: []
            shortcut: ew
            disabled: true
            about:
              website: https://www.erowid.org/
              wikidata_id: Q1430691
              official_api_documentation:
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: wikidata
            engine: wikidata
            shortcut: wd
            timeout: 3.0
            weight: 2
            tests: *tests_infobox

          - name: duckduckgo
            engine: duckduckgo
            shortcut: ddg

          - name: duckduckgo images
            engine: duckduckgo_images
            shortcut: ddi
            timeout: 3.0

          - name: duckduckgo weather
            engine: duckduckgo_weather
            shortcut: ddw
            disabled: true

          - name: apple maps
            engine: apple_maps
            shortcut: apm
            disabled: true
            timeout: 5.0

          - name: emojipedia
            engine: emojipedia
            timeout: 4.0
            shortcut: em
            disabled: true

          - name: etymonline
            engine: xpath
            paging: true
            search_url: https://etymonline.com/search?page={pageno}&q={query}
            url_xpath: //a[contains(@class, "word__name--")]/@href
            title_xpath: //a[contains(@class, "word__name--")]
            content_xpath: //section[contains(@class, "word__defination")]
            first_page_num: 1
            shortcut: et
            categories: [dictionaries]
            disabled: false
            about:
              website: https://www.etymonline.com/
              wikidata_id: Q1188617
              official_api_documentation:
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: 1x
            engine: www1x
            shortcut: 1x
            timeout: 3.0
            disabled: true

          - name: fdroid
            engine: fdroid
            shortcut: fd

          - name: flickr
            categories: images
            shortcut: fl
            # You can use the engine using the official stable API, but you need an API
            # key, see: https://www.flickr.com/services/apps/create/
            # engine: flickr
            # api_key: 'apikey' # required!
            # Or you can use the html non-stable engine, activated by default
            engine: flickr_noapi
            disabled: true

          - name: free software directory
            engine: mediawiki
            shortcut: fsd
            categories: [it, software wikis]
            base_url: https://directory.fsf.org/
            number_of_results: 5
            # what part of a page matches the query string: title, text, nearmatch
            # * title     - query matches title
            # * text      - query matches the text of page
            # * nearmatch - nearmatch in title
            search_type: title
            timeout: 5.0
            disabled: true
            about:
              website: https://directory.fsf.org/
              wikidata_id: Q2470288

          - name: frinkiac
            engine: frinkiac
            shortcut: frk
            disabled: true

          - name: genius
            engine: genius
            shortcut: gen

          - name: gentoo
            engine: gentoo
            shortcut: ge

          - name: gitlab
            engine: json_engine
            paging: true
            search_url: https://gitlab.com/api/v4/projects?search={query}&page={pageno}
            url_query: web_url
            title_query: name_with_namespace
            content_query: description
            page_size: 20
            categories: [it, repos]
            shortcut: gl
            timeout: 10.0
            disabled: true
            about:
              website: https://about.gitlab.com/
              wikidata_id: Q16639197
              official_api_documentation: https://docs.gitlab.com/ee/api/
              use_official_api: false
              require_api_key: false
              results: JSON

          - name: github
            engine: github
            shortcut: gh

            # This a Gitea service. If you would like to use a different instance,
            # change codeberg.org to URL of the desired Gitea host. Or you can create a
            # new engine by copying this and changing the name, shortcut and search_url.

          - name: codeberg
            engine: json_engine
            search_url: https://codeberg.org/api/v1/repos/search?q={query}&limit=10
            url_query: html_url
            title_query: name
            content_query: description
            categories: [it, repos]
            shortcut: cb
            disabled: true
            about:
              website: https://codeberg.org/
              wikidata_id:
              official_api_documentation: https://try.gitea.io/api/swagger
              use_official_api: false
              require_api_key: false
              results: JSON

          - name: google
            engine: google
            shortcut: go
            # see https://docs.searxng.org/src/searx.engines.google.html#module-searx.engines.google
            use_mobile_ui: false
            # additional_tests:
            #   android: *test_android

          # - name: google italian
          #   engine: google
          #   shortcut: goit
          #   use_mobile_ui: false
          #   language: it

          # - name: google mobile ui
          #   engine: google
          #   shortcut: gomui
          #   use_mobile_ui: true

          - name: google images
            engine: google_images
            shortcut: goi
            # additional_tests:
            #   android: *test_android
            #   dali:
            #     matrix:
            #       query: ['Dali Christ']
            #       lang: ['en', 'de', 'fr', 'zh-CN']
            #     result_container:
            #       - ['one_title_contains', 'Salvador']

          - name: google news
            engine: google_news
            shortcut: gon
            # additional_tests:
            #   android: *test_android

          - name: google videos
            engine: google_videos
            shortcut: gov
            # additional_tests:
            #   android: *test_android

          - name: google scholar
            engine: google_scholar
            shortcut: gos

          - name: gpodder
            engine: json_engine
            shortcut: gpod
            timeout: 4.0
            paging: false
            search_url: https://gpodder.net/search.json?q={query}
            url_query: url
            title_query: title
            content_query: description
            page_size: 19
            categories: music
            disabled: true
            about:
              website: https://gpodder.net
              wikidata_id: Q3093354
              official_api_documentation: https://gpoddernet.readthedocs.io/en/latest/api/
              use_official_api: false
              requires_api_key: false
              results: JSON

          - name: habrahabr
            engine: xpath
            paging: true
            search_url: https://habrahabr.ru/search/page{pageno}/?q={query}
            url_xpath: //article[contains(@class, "post")]//a[@class="post__title_link"]/@href
            title_xpath: //article[contains(@class, "post")]//a[@class="post__title_link"]
            content_xpath: //article[contains(@class, "post")]//div[contains(@class, "post__text")]
            categories: it
            timeout: 4.0
            disabled: true
            shortcut: habr
            about:
              website: https://habr.com/
              wikidata_id: Q4494434
              official_api_documentation: https://habr.com/en/docs/help/api/
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: hoogle
            engine: xpath
            paging: true
            search_url: https://hoogle.haskell.org/?hoogle={query}&start={pageno}
            results_xpath: '//div[@class="result"]'
            title_xpath: './/div[@class="ans"]//a'
            url_xpath: './/div[@class="ans"]//a/@href'
            content_xpath: './/div[@class="from"]'
            page_size: 20
            categories: [it, packages]
            shortcut: ho
            disabled: true
            about:
              website: https://hoogle.haskell.org/
              wikidata_id: Q34010
              official_api_documentation: https://hackage.haskell.org/api
              use_official_api: false
              require_api_key: false
              results: JSON

          - name: imdb
            engine: imdb
            shortcut: imdb
            timeout: 6.0
            disabled: true

          - name: ina
            engine: ina
            shortcut: in
            timeout: 6.0
            disabled: true

          - name: jisho
            engine: jisho
            shortcut: js
            timeout: 3.0
            disabled: true

          - name: kickass
            engine: kickass
            shortcut: kc
            timeout: 4.0

          - name: library genesis
            engine: xpath
            search_url: https://libgen.fun/search.php?req={query}
            url_xpath: //a[contains(@href,"get.php?md5")]/@href
            title_xpath: //a[contains(@href,"book/")]/text()[1]
            content_xpath: //td/a[1][contains(@href,"=author")]/text()
            categories: files
            timeout: 7.0
            shortcut: lg
            about:
              website: https://libgen.fun/
              wikidata_id: Q22017206
              official_api_documentation:
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: library of congress
            engine: loc
            shortcut: loc
            categories: images

          - name: lingva
            engine: lingva
            shortcut: lv
            disabled: true
            # set lingva instance in url, by default it will use the official instance
            # url: https://lingva.ml

          - name: lobste.rs
            engine: xpath
            search_url: https://lobste.rs/search?utf8=%E2%9C%93&q={query}&what=stories&order=relevance
            results_xpath: //li[contains(@class, "story")]
            url_xpath: .//a[@class="u-url"]/@href
            title_xpath: .//a[@class="u-url"]
            content_xpath: .//a[@class="domain"]
            categories: it
            shortcut: lo
            timeout: 5.0
            disabled: true
            about:
              website: https://lobste.rs/
              wikidata_id: Q60762874
              official_api_documentation:
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: azlyrics
            shortcut: lyrics
            engine: xpath
            timeout: 4.0
            disabled: true
            categories: [music, lyrics]
            paging: true
            search_url: https://search.azlyrics.com/search.php?q={query}&w=lyrics&p={pageno}
            url_xpath: //td[@class="text-left visitedlyr"]/a/@href
            title_xpath: //span/b/text()
            content_xpath: //td[@class="text-left visitedlyr"]/a/small
            about:
              website: https://azlyrics.com
              wikidata_id: Q66372542
              official_api_documentation:
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: metacpan
            engine: metacpan
            shortcut: cpan
            disabled: true
            number_of_results: 20

          # - name: meilisearch
          #   engine: meilisearch
          #   shortcut: mes
          #   enable_http: true
          #   base_url: http://localhost:7700
          #   index: my-index

          - name: mixcloud
            engine: mixcloud
            shortcut: mc

          - name: neeva
            engine: xpath
            shortcut: nv
            time_range_support: true
            time_range_url: '&alf%5Bfreshness%5D={time_range_val}'
            time_range_map:
              day: 'Day'
              week: 'Week'
              month: 'Month'
              year: 'Year'
            search_url: https://neeva.com/search?q={query}&c=All&src=Pagination&page={pageno}{time_range}
            results_xpath: //div[@class="web-index__component-2rKiM"] | //li[@class="web-rich-deep-links__deepLink-SIbD4"]
            url_xpath: .//a[@class="lib-doc-title__link-1b9rC"]/@href | ./h2/a/@href
            title_xpath: .//a[@class="lib-doc-title__link-1b9rC"] | ./h2/a
            content_xpath: >
              .//div[@class="lib-doc-snippet__component-3ewW6"]/text() |
              .//div[@class="lib-doc-snippet__component-3ewW6"]/*[not(self::a)] |
              ./p
            content_html_to_text: true
            suggestion_xpath: //span[@class="result-related-searches__link-2ho_u"]
            paging: true
            disabled: true
            categories: [general, web]
            timeout: 5.0
            soft_max_redirects: 2
            about:
              website: https://neeva.com
              official_api_documentation:
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: npm
            engine: json_engine
            paging: true
            first_page_num: 0
            search_url: https://api.npms.io/v2/search?q={query}&size=25&from={pageno}
            results_query: results
            url_query: package/links/npm
            title_query: package/name
            content_query: package/description
            page_size: 25
            categories: [it, packages]
            timeout: 5.0
            shortcut: npm
            about:
              website: https://npms.io/
              wikidata_id: Q7067518
              official_api_documentation: https://api-docs.npms.io/
              use_official_api: false
              require_api_key: false
              results: JSON

          - name: nyaa
            engine: nyaa
            shortcut: nt
            disabled: true

          - name: mankier
            engine: json_engine
            search_url: https://www.mankier.com/api/v2/mans/?q={query}
            results_query: results
            url_query: url
            title_query: name
            content_query: description
            categories: it
            shortcut: man
            about:
              website: https://www.mankier.com/
              official_api_documentation: https://www.mankier.com/api
              use_official_api: true
              require_api_key: false
              results: JSON

          - name: openairedatasets
            engine: json_engine
            paging: true
            search_url: https://api.openaire.eu/search/datasets?format=json&page={pageno}&size=10&title={query}
            results_query: response/results/result
            url_query: metadata/oaf:entity/oaf:result/children/instance/webresource/url/$
            title_query: metadata/oaf:entity/oaf:result/title/$
            content_query: metadata/oaf:entity/oaf:result/description/$
            content_html_to_text: true
            categories: "science"
            shortcut: oad
            timeout: 5.0
            about:
              website: https://www.openaire.eu/
              wikidata_id: Q25106053
              official_api_documentation: https://api.openaire.eu/
              use_official_api: false
              require_api_key: false
              results: JSON

          - name: openairepublications
            engine: json_engine
            paging: true
            search_url: https://api.openaire.eu/search/publications?format=json&page={pageno}&size=10&title={query}
            results_query: response/results/result
            url_query: metadata/oaf:entity/oaf:result/children/instance/webresource/url/$
            title_query: metadata/oaf:entity/oaf:result/title/$
            content_query: metadata/oaf:entity/oaf:result/description/$
            content_html_to_text: true
            categories: science
            shortcut: oap
            timeout: 5.0
            about:
              website: https://www.openaire.eu/
              wikidata_id: Q25106053
              official_api_documentation: https://api.openaire.eu/
              use_official_api: false
              require_api_key: false
              results: JSON

          # - name: opensemanticsearch
          #   engine: opensemantic
          #   shortcut: oss
          #   base_url: 'http://localhost:8983/solr/opensemanticsearch/'

          - name: openstreetmap
            engine: openstreetmap
            shortcut: osm

          - name: openrepos
            engine: xpath
            paging: true
            search_url: https://openrepos.net/search/node/{query}?page={pageno}
            url_xpath: //li[@class="search-result"]//h3[@class="title"]/a/@href
            title_xpath: //li[@class="search-result"]//h3[@class="title"]/a
            content_xpath: //li[@class="search-result"]//div[@class="search-snippet-info"]//p[@class="search-snippet"]
            categories: files
            timeout: 4.0
            disabled: true
            shortcut: or
            about:
              website: https://openrepos.net/
              wikidata_id:
              official_api_documentation:
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: packagist
            engine: json_engine
            paging: true
            search_url: https://packagist.org/search.json?q={query}&page={pageno}
            results_query: results
            url_query: url
            title_query: name
            content_query: description
            categories: [it, packages]
            disabled: true
            timeout: 5.0
            shortcut: pack
            about:
              website: https://packagist.org
              wikidata_id: Q108311377
              official_api_documentation: https://packagist.org/apidoc
              use_official_api: true
              require_api_key: false
              results: JSON

          - name: pdbe
            engine: pdbe
            shortcut: pdb
            # Hide obsolete PDB entries.  Default is not to hide obsolete structures
            #  hide_obsolete: false

          - name: photon
            engine: photon
            shortcut: ph

          - name: piratebay
            engine: piratebay
            shortcut: tpb
            # You may need to change this URL to a proxy if piratebay is blocked in your
            # country
            url: https://thepiratebay.org/
            timeout: 3.0
            disabled: true

          - name: pub.dev
            engine: xpath
            shortcut: pd
            search_url: https://pub.dev/packages?q={query}&page={pageno}
            paging: true
            results_xpath: /html/body/main/div/div[@class="search-results"]/div[@class="packages"]/div
            url_xpath: ./div/h3/a/@href
            title_xpath: ./div/h3/a
            content_xpath: ./p[@class="packages-description"]
            categories: [packages, it]
            timeout: 3.0
            disabled: true
            first_page_num: 1
            about:
              website: https://pub.dev/
              official_api_documentation: https://pub.dev/help/api
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: pubmed
            engine: pubmed
            shortcut: pub
            timeout: 3.0

          - name: pypi
            shortcut: pypi
            engine: xpath
            paging: true
            search_url: https://pypi.org/search?q={query}&page={pageno}
            results_xpath: /html/body/main/div/div/div/form/div/ul/li/a[@class="package-snippet"]
            url_xpath: ./@href
            title_xpath: ./h3/span[@class="package-snippet__name"]
            content_xpath: ./p
            suggestion_xpath: /html/body/main/div/div/div/form/div/div[@class="callout-block"]/p/span/a[@class="link"]
            first_page_num: 1
            categories: [it, packages]
            about:
              website: https://pypi.org
              wikidata_id: Q2984686
              official_api_documentation: https://warehouse.readthedocs.io/api-reference/index.html
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: qwant
            qwant_categ: web
            engine: qwant
            shortcut: qw
            categories: [general, web]
            disabled: false
            additional_tests:
              rosebud: *test_rosebud

          - name: qwant news
            qwant_categ: news
            engine: qwant
            shortcut: qwn
            categories: news
            disabled: false
            network: qwant

          - name: qwant images
            qwant_categ: images
            engine: qwant
            shortcut: qwi
            categories: [images, web]
            disabled: false
            network: qwant

          - name: qwant videos
            qwant_categ: videos
            engine: qwant
            shortcut: qwv
            categories: [videos, web]
            disabled: false
            network: qwant

          - name: soundcloud
            engine: soundcloud
            shortcut: sc

          - name: stackoverflow
            engine: stackexchange
            shortcut: st
            api_site: 'stackoverflow'
            categories: [it, q&a]

          - name: askubuntu
            engine: stackexchange
            shortcut: ubuntu
            api_site: 'askubuntu'
            categories: [it, q&a]

          - name: superuser
            engine: stackexchange
            shortcut: su
            api_site: 'superuser'
            categories: [it, q&a]

          - name: searchcode code
            engine: searchcode_code
            shortcut: scc
            disabled: true

          - name: framalibre
            engine: framalibre
            shortcut: frl
            disabled: true

          - name: semantic scholar
            engine: semantic_scholar
            disabled: true
            shortcut: se

          - name: startpage
            engine: startpage
            shortcut: sp
            timeout: 6.0
            disabled: true
            additional_tests:
              rosebud: *test_rosebud

          - name: tokyotoshokan
            engine: tokyotoshokan
            shortcut: tt
            timeout: 6.0
            disabled: true

          - name: solidtorrents
            engine: solidtorrents
            shortcut: solid
            timeout: 4.0
            disabled: true
            base_url:
              - https://solidtorrents.net
              - https://solidtorrents.eu
              - https://solidtorrents.to
              - https://bitsearch.to

          # torznab engine lets you query any torznab compatible indexer.  Using this
          # engine in combination with Jackett (https://github.com/Jackett/Jackett)
          # opens the possibility to query a lot of public and private indexers directly
          # from SearXNG.
          # - name: torznab
          #   engine: torznab
          #   shortcut: trz
          #   base_url: http://localhost:9117/api/v2.0/indexers/all/results/torznab
          #   enable_http: true  # if using localhost
          #   api_key: xxxxxxxxxxxxxxx
          #   # https://github.com/Jackett/Jackett/wiki/Jackett-Categories
          #   torznab_categories:  # optional
          #     - 2000
          #     - 5000

          - name: twitter
            shortcut: tw
            engine: twitter
            disabled: true

          # maybe in a fun category
          #  - name: uncyclopedia
          #    engine: mediawiki
          #    shortcut: unc
          #    base_url: https://uncyclopedia.wikia.com/
          #    number_of_results: 5

          - name: unsplash
            engine: unsplash
            shortcut: us

          - name: youtube
            shortcut: yt
            # You can use the engine using the official stable API, but you need an API
            # key See: https://console.developers.google.com/project
            #
            # engine: youtube_api
            # api_key: 'apikey' # required!
            #
            # Or you can use the html non-stable engine, activated by default
            engine: youtube_noapi

          - name: dailymotion
            engine: dailymotion
            shortcut: dm
            disabled: true

          - name: vimeo
            engine: vimeo
            shortcut: vm
            disabled: true

          - name: wiby
            engine: json_engine
            search_url: https://wiby.me/json/?q={query}
            url_query: URL
            title_query: Title
            content_query: Snippet
            categories: [general, web]
            shortcut: wib
            disabled: true
            about:
              website: https://wiby.me/

          - name: marginalia
            engine: json_engine
            shortcut: mar
            categories: general
            paging: false
            # index: {"0": "popular", "1": "blogs", "2": "big_sites",
            # "3": "default", "4": experimental"}
            search_url: https://api.marginalia.nu/public/search/{query}?index=4&count=20
            results_query: results
            url_query: url
            title_query: title
            content_query: description
            timeout: 1.5
            disabled: true
            about:
              website: https://www.marginalia.nu/
              official_api_documentation: https://api.marginalia.nu/
              use_official_api: true
              require_api_key: true
              results: JSON

          - name: alexandria
            engine: json_engine
            shortcut: alx
            categories: general
            paging: true
            search_url: https://api.alexandria.org/?a=1&q={query}&p={pageno}
            results_query: results
            title_query: title
            url_query: url
            content_query: snippet
            timeout: 1.5
            disabled: true
            about:
              website: https://alexandria.org/
              official_api_documentation: https://github.com/alexandria-org/alexandria-api/raw/master/README.md
              use_official_api: true
              require_api_key: false
              results: JSON

          - name: wikibooks
            engine: mediawiki
            shortcut: wb
            categories: general
            base_url: "https://{language}.wikibooks.org/"
            number_of_results: 5
            search_type: text
            disabled: true
            about:
              website: https://www.wikibooks.org/
              wikidata_id: Q367

          - name: wikinews
            engine: mediawiki
            shortcut: wn
            categories: news
            base_url: "https://{language}.wikinews.org/"
            number_of_results: 5
            search_type: text
            disabled: true
            about:
              website: https://www.wikinews.org/
              wikidata_id: Q964

          - name: wikiquote
            engine: mediawiki
            shortcut: wq
            categories: general
            base_url: "https://{language}.wikiquote.org/"
            number_of_results: 5
            search_type: text
            disabled: true
            additional_tests:
              rosebud: *test_rosebud
            about:
              website: https://www.wikiquote.org/
              wikidata_id: Q369

          - name: wikisource
            engine: mediawiki
            shortcut: ws
            categories: general
            base_url: "https://{language}.wikisource.org/"
            number_of_results: 5
            search_type: text
            disabled: true
            about:
              website: https://www.wikisource.org/
              wikidata_id: Q263

          - name: wiktionary
            engine: mediawiki
            shortcut: wt
            categories: [dictionaries]
            base_url: "https://{language}.wiktionary.org/"
            number_of_results: 5
            search_type: text
            disabled: false
            about:
              website: https://www.wiktionary.org/
              wikidata_id: Q151

          - name: wikiversity
            engine: mediawiki
            shortcut: wv
            categories: general
            base_url: "https://{language}.wikiversity.org/"
            number_of_results: 5
            search_type: text
            disabled: true
            about:
              website: https://www.wikiversity.org/
              wikidata_id: Q370

          - name: wikivoyage
            engine: mediawiki
            shortcut: wy
            categories: general
            base_url: "https://{language}.wikivoyage.org/"
            number_of_results: 5
            search_type: text
            disabled: true
            about:
              website: https://www.wikivoyage.org/
              wikidata_id: Q373

          - name: wolframalpha
            shortcut: wa
            # You can use the engine using the official stable API, but you need an API
            # key.  See: https://products.wolframalpha.com/api/
            #
            # engine: wolframalpha_api
            # api_key: ''
            #
            # Or you can use the html non-stable engine, activated by default
            engine: wolframalpha_noapi
            timeout: 6.0
            categories: []

          - name: dictzone
            engine: dictzone
            shortcut: dc
            disabled: true

          - name: mymemory translated
            engine: translated
            shortcut: tl
            timeout: 5.0
            disabled: false
            # You can use without an API key, but you are limited to 1000 words/day
            # See: https://mymemory.translated.net/doc/usagelimits.php
            # api_key: ''

          - name: 1337x
            engine: 1337x
            shortcut: 1337x

          - name: duden
            engine: duden
            shortcut: du
            disabled: true

          - name: seznam
            shortcut: szn
            engine: seznam
            disabled: true

          - name: mojeek
            shortcut: mjk
            engine: xpath
            paging: true
            categories: [general, web]
            search_url: https://www.mojeek.com/search?q={query}&s={pageno}
            results_xpath: //a[@class="ob"]
            url_xpath: ./@href
            title_xpath: ./h2
            content_xpath: ../p[@class="s"]
            suggestion_xpath: /html/body//div[@class="top-info"]/p[@class="top-info spell"]/a
            first_page_num: 0
            page_size: 10
            disabled: true
            about:
              website: https://www.mojeek.com/
              wikidata_id: Q60747299
              official_api_documentation: https://www.mojeek.com/services/api.html/
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: naver
            shortcut: nvr
            categories: [general, web]
            engine: xpath
            paging: true
            search_url: https://search.naver.com/search.naver?where=webkr&sm=osp_hty&ie=UTF-8&query={query}&start={pageno}
            url_xpath: //a[@class="link_tit"]/@href
            title_xpath: //a[@class="link_tit"]
            content_xpath: //a[@class="total_dsc"]/div
            first_page_num: 1
            page_size: 10
            disabled: true
            about:
              website: https://www.naver.com/
              wikidata_id: Q485639
              official_api_documentation: https://developers.naver.com/docs/nmt/examples/
              use_official_api: false
              require_api_key: false
              results: HTML
              language: ko

          - name: rubygems
            shortcut: rbg
            engine: xpath
            paging: true
            search_url: https://rubygems.org/search?page={pageno}&query={query}
            results_xpath: /html/body/main/div/a[@class="gems__gem"]
            url_xpath: ./@href
            title_xpath: ./span/h2
            content_xpath: ./span/p
            suggestion_xpath: /html/body/main/div/div[@class="search__suggestions"]/p/a
            first_page_num: 1
            categories: [it, packages]
            disabled: true
            about:
              website: https://rubygems.org/
              wikidata_id: Q1853420
              official_api_documentation: https://guides.rubygems.org/rubygems-org-api/
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: peertube
            engine: peertube
            shortcut: ptb
            paging: true
            # https://instances.joinpeertube.org/instances
            base_url: https://peertube.biz/
            # base_url: https://tube.tardis.world/
            categories: videos
            disabled: true
            timeout: 6.0

          - name: mediathekviewweb
            engine: mediathekviewweb
            shortcut: mvw
            disabled: true

          - name: rumble
            engine: rumble
            shortcut: ru
            base_url: https://rumble.com/
            paging: true
            categories: videos
            disabled: true

          - name: wordnik
            engine: wordnik
            shortcut: def
            base_url: https://www.wordnik.com/
            categories: [dictionaries]
            timeout: 5.0
            disabled: false

          - name: woxikon.de synonyme
            engine: xpath
            shortcut: woxi
            categories: [dictionaries]
            timeout: 5.0
            disabled: true
            search_url: https://synonyme.woxikon.de/synonyme/{query}.php
            url_xpath: //div[@class="upper-synonyms"]/a/@href
            content_xpath: //div[@class="synonyms-list-group"]
            title_xpath: //div[@class="upper-synonyms"]/a
            no_result_for_http_status: [404]
            about:
              website: https://www.woxikon.de/
              wikidata_id:  # No Wikidata ID
              use_official_api: false
              require_api_key: false
              results: HTML
              language: de

          - name: sjp.pwn
            engine: sjp
            shortcut: sjp
            base_url: https://sjp.pwn.pl/
            timeout: 5.0
            disabled: true

            # wikimini: online encyclopedia for children
            # The fulltext and title parameter is necessary for Wikimini because
            # sometimes it will not show the results and redirect instead
          - name: wikimini
            engine: xpath
            shortcut: wkmn
            search_url: https://fr.wikimini.org/w/index.php?search={query}&title=Sp%C3%A9cial%3ASearch&fulltext=Search
            url_xpath: //li/div[@class="mw-search-result-heading"]/a/@href
            title_xpath: //li//div[@class="mw-search-result-heading"]/a
            content_xpath: //li/div[@class="searchresult"]
            categories: general
            disabled: true
            about:
              website: https://wikimini.org/
              wikidata_id: Q3568032
              use_official_api: false
              require_api_key: false
              results: HTML
              language: fr

          - name: wttr.in
            engine: wttr
            shortcut: wttr
            timeout: 9.0

          - name: brave
            shortcut: brave
            engine: xpath
            paging: true
            time_range_support: true
            first_page_num: 0
            time_range_url: "&tf={time_range_val}"
            search_url: https://search.brave.com/search?q={query}&offset={pageno}&spellcheck=1{time_range}
            url_xpath: //a[@class="result-header"]/@href
            title_xpath: //span[@class="snippet-title"]
            content_xpath: //p[1][@class="snippet-description"]
            suggestion_xpath: //div[@class="text-gray h6"]/a
            time_range_map:
              day: 'pd'
              week: 'pw'
              month: 'pm'
              year: 'py'
            categories: [general, web]
            headers:
              Accept-Encoding: gzip, deflate
            about:
              website: https://brave.com/search/
              wikidata_id: Q107355971
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: lib.rs
            shortcut: lrs
            engine: xpath
            search_url: https://lib.rs/search?q={query}
            results_xpath: /html/body/main/div/ol/li/a
            url_xpath: ./@href
            title_xpath: ./div[@class="h"]/h4
            content_xpath: ./div[@class="h"]/p
            categories: [it, packages]
            disabled: true
            about:
              website: https://lib.rs
              wikidata_id: Q113486010
              use_official_api: false
              require_api_key: false
              results: HTML

          - name: sourcehut
            shortcut: srht
            engine: xpath
            paging: true
            search_url: https://sr.ht/projects?page={pageno}&search={query}
            results_xpath: (//div[@class="event-list"])[1]/div[@class="event"]
            url_xpath: ./h4/a[2]/@href
            title_xpath: ./h4/a[2]
            content_xpath: ./p
            first_page_num: 1
            categories: [it, repos]
            disabled: true
            about:
              website: https://sr.ht
              wikidata_id: Q78514485
              official_api_documentation: https://man.sr.ht/
              use_official_api: false
              require_api_key: false
              results: HTML

        doi_resolvers:
          oadoi.org: 'https://oadoi.org/'
          doi.org: 'https://doi.org/'
          doai.io: 'https://dissem.in/'
          sci-hub.se: 'https://sci-hub.se/'
          sci-hub.st: 'https://sci-hub.st/'
          sci-hub.ru: 'https://sci-hub.ru/'

        default_doi_resolver: 'oadoi.org'
      |||,
      "uwsgi.ini": |||
        [uwsgi]
        # Who will run the code
        uid = searxng
        gid = searxng

        # Number of workers/processes (usually CPU count).
        # Reduced since they use a lot of resources.
        workers = 2
        threads = 2

        # The right granted on the created socket
        chmod-socket = 666

        # Plugin to use and interpreter config
        single-interpreter = true
        master = true
        plugin = python3
        lazy-apps = true
        enable-threads = true

        # Module to import
        module = searx.webapp

        # Virtualenv and python path
        pythonpath = /usr/local/searxng/
        chdir = /usr/local/searxng/searx/

        # automatically set processes name to something meaningful
        auto-procname = true

        # Disable request logging for privacy
        disable-logging = true
        log-5xx = true

        # Set the max size of a request (request-body excluded)
        buffer-size = 8192

        # No keep alive
        # See https://github.com/searx/searx-docker/issues/24
        add-header = Connection: close

        # uwsgi serves the static files
        # expires set to one year since there are hashes
        static-map = /static=/usr/local/searxng/searx/static
        static-expires = /* 31557600
        static-gzip-all = True
        offload-threads = %k

        # Cache
        cache2 = name=searxngcache,items=2000,blocks=2000,blocksize=4096,bitmap=1
      |||
    },
  },
}

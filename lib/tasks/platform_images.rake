require 'nokogiri'
require 'net/http'
require 'openssl'

module Platform
  module Images
    CATALOGS_DOCS = {
      "distributions" => { "docs" => "compute/catalog/distributions", "segments" => 2 },
      "platforms"     => { "docs" => "compute/catalog/platforms",     "segments" => 2 },
      "applications"  => { "docs" => "compute/catalog/apps",          "segments" => 1 }
    }.freeze

    HEADINGS = {
      "summary"            => { "en" => ["Summary"],           "ru" => ["Summary"] },
      "overview"           => { "en" => ["Overview"],          "ru" => ["Обзор"] },
      "description"        => { "en" => ["description"],        "ru" => ["описание"] },
      "features"           => { "en" => ["features"],           "ru" => ["характеристики"] },
      "disk-partitioning"  => { "en" => ["disk partitioning"],  "ru" => ["схема разделов диска"] },
      "configuration"      => { "en" => ["configuration"],      "ru" => ["конфигурация"] },
      "installed-software" => { "en" => ["installed software"], "ru" => ["установленное по"] },
      "license"            => { "en" => ["license"],            "ru" => ["лицензия", "лицензии"] }
    }.freeze

    SECTIONS = HEADINGS.keys.freeze

    ATTRIBUTE_ROWS = {
      "os"             => { "en" => ["Operating System", "Version"], "ru" => ["Операционная система", "Версия"] },
      "os_release"     => { "en" => ["OS Release"], "ru" => ["Релиз ОС"] },
      "license"        => { "en" => ["License"], "ru" => ["Лицензия", "Лицензии"] },
      "supported_by"   => { "en" => ["Supported By", "Supported by"], "ru" => ["Поддерживается"] },
      "canonical_name" => { "en" => ["Canonical name"], "ru" => ["Каноническое имя"] }
    }.freeze

    class << self
      def config
        @config ||= {
          base_url:     ENV.fetch('DOCS_BASE_URL', 'https://docs.icdc.io'),
          languages:    ENV.fetch('LANGUAGES', 'en,ru').split(',').map(&:strip),
          name:         ENV.fetch('NAME', ''),
          doc_url:      ENV.fetch('DOC_URL', ''),
          supported_by: ENV.fetch('SUPPORTED_BY', 'ICDC Team'),
          dry_run:      ENV['DRY_RUN'] == '1'
        }
      end

      def sync
        if !config[:doc_url].empty? && config[:name].empty?
          abort "ERROR: DOC_URL requires NAME=<image name>"
        end

        list = images
        log "Images: #{list.size}, catalogs: #{catalogs(list).join(', ')}"

        pages = fetch_catalog_pages(catalogs(list))
        log "Dry run: nothing will be written" if config[:dry_run]

        stats = Hash.new(0)
        list.each { |image| stats[sync_image(image, pages)] += 1 }

        log '-' * 60
        log "Updated: #{stats[:updated]}, unchanged: #{stats[:unchanged]}"
        log "Would be updated (dry run): #{stats[:dry_run]}" if config[:dry_run]
        log "Skipped (no documentation page): #{stats[:no_page]}, errors: #{stats[:error]}"
      end

      def images
        all = ServiceTemplate.in_my_region.where(:display => true).includes(:service_template_catalog)
        return all if config[:name].empty?

        all.find_all { |image| image.name.to_s.casecmp(config[:name]).zero? }
      end

      def catalogs(list)
        names = list.map { |image| catalog_key(image.service_template_catalog&.name) }
        (CATALOGS_DOCS.keys & names.uniq).sort
      end

      # Fills the description and the attributes of a single image.
      # Returns :updated, :unchanged, :no_page or :error.
      def sync_image(image, pages)
        cfg     = config
        lang    = cfg[:languages].first

        catalog_type = image.service_template_catalog&.name
        catalog     = catalog_key(catalog_type)
        page_urls   = pages[catalog]

        url = documentation_url(image, page_urls, catalog, catalog_type)
        return :no_page if url.nil?

        parsed = {}
        cfg[:languages].each do |current|
          current_url = url.sub("/#{lang}/", "/#{current}/")
          begin
            page = parse_page(current_url)
            parsed[current] = page if page
          rescue StandardError => e
            log "Error: can not parse page [#{current_url}] #{e.class}: #{e.message}"
          end
        end
        if parsed.empty?
          log "Error [#{image.name}]: no documentation page could be parsed"
          return :error
        end
        parsed[lang] ||= parsed.values.first

        description = build_description(parsed)
        attributes  = image_attributes(parsed[lang], url)
        changed     = description != image.long_description

        log "[SYNC] [#{image.name}] #{url}"
        log "  long_description: #{changed ? 'CHANGED' : 'unchanged'} (#{description.length} characters)"
        attributes.each { |key, value| log "  #{key}: #{value}" }

        return :unchanged unless changed

        return :dry_run if config[:dry_run]

        image.update(:long_description => description)
        attributes.each { |key, value| image.miq_custom_set(key, value) }
        :updated
      rescue StandardError => e
        log "Error [#{image.name}]: #{e.class}: #{e.message}"
        :error
      end

      def documentation_url(image, page_urls, catalog, catalog_type)
        unless config[:doc_url].to_s.empty?
          log "URL [#{image.name}]: DOC_URL option"
          return config[:doc_url]
        end

        stored = image.miq_custom_get('doc').to_s
        unless stored.empty?
          log "URL [#{image.name}]: doc attribute"
          return stored
        end

        if page_urls.nil?
          log "Skip [#{image.name}]: catalog [#{catalog_type}] is not documented"
          return nil
        end

        name, version = image.name.to_s.split(':', 2)
        if version.to_s.strip.empty?
          log "Skip [#{image.name}]: name does not follow the <name>:<version> format"
          return nil
        end

        url = find_page_url(name, version, page_urls, catalog)
        if url.nil?
          log "Skip [#{image.name}]: no documentation page for version [#{version}] in catalog [#{catalog_type}]"
        end
        url
      end

      def catalog_key(catalog_name)
        catalog_name.to_s.strip.downcase
      end

      def catalog_docs(catalog)
        CATALOGS_DOCS[catalog_key(catalog)]
      end

      # The documentation url path of a catalog, e.g. "distributions" => "compute/catalog/distributions".
      def catalog_docs_path(catalog)
        catalog_docs(catalog).fetch("docs")
      end

      # The number of path segments between the catalog folder and a page of it.
      def catalog_segments(catalog)
        catalog_docs(catalog).fetch("segments")
      end

      def fetch_catalog_pages(list)
        list.each_with_object({}) do |catalog, result|
          result[catalog] = fetch_site_pages(catalog)
        end
      end

      def find_page_url(name, version, page_urls, catalog = nil)
        return page_urls.first if page_urls.size == 1
        return canonical_page_url(name, version, page_urls) unless path_match?(catalog)

        page_urls.find do |url|
          distribution, page_version = distribution_and_version(url)
          page_version == version && distribution.tr('_', ' ').casecmp?(name.to_s)
        end
      end

      def path_match?(catalog)
        catalog_key(catalog) == 'distributions'
      end

      def canonical_page_url(name, version, candidates)
        full_name = "#{name}:#{version}"
        candidates.each do |url|
          page     = parse_page(url)
          canonical = page&.dig(:features, 'canonical_name')
          return url if canonical && canonical.casecmp?(full_name)
        end
        nil
      end

      def distribution_and_version(url)
        parts = url.chomp('/').split('/')
        [parts[-2].to_s, parts[-1].to_s]
      end

      def build_description(parsed)
        languages = config[:languages].select { |lang| parsed.key?(lang) }
        blocks = languages.map { |lang| "# Docs [#{lang}]\n\n#{language_block(lang, parsed[lang])}" }
        body = "#{blocks.join("\n\n----\n\n")}\n"

        # For Compute v3 dedicated UI compatibility: a plain text summary followed by 40 spaces
        lang = config[:languages].first
        summary = section_markdown(parsed[lang][:sections]['description'])
        summary = parsed[lang][:title].to_s if summary.empty?
        "#{summary}#{' ' * 40}\n\n#{body}"
      end

      def language_block(lang, page)
        sections = page[:sections]
        summary  = section_markdown(sections['description'])
        summary  = page[:title].to_s if summary.empty?
        blocks   = ["## #{HEADINGS["summary"][lang].first} {#summary}", summary]

        screenshots = section_images(sections['overview'])
        blocks << "## #{HEADINGS["overview"][lang].first} {#overview}"
        blocks << screenshots.join("\n") unless screenshots.empty?

        SECTIONS.each do |id|
          next if id == 'overview'
          section = sections[id]
          next if section.nil? || section[:blocks].reject(&:empty?).empty?
          blocks << format("### %s {#%s}", section[:heading], id)
          blocks << section_markdown(section)
        end

        blocks.reject(&:empty?).join("\n\n")
      end

      def section_markdown(section)
        return '' if section.nil?
        section[:blocks].reject(&:empty?).join("\n\n")
      end

      def section_images(section)
        section ? section[:blocks].grep(/^!\[[^\]]*\]\([^)]+\)/) : []
      end

      def image_attributes(page, url)
        values = page[:features]
        result = { 'doc' => url }

        os = [values['os'], values['os_release']].compact.reject(&:empty?).join(' ')
        result['os'] = os unless os.empty?
        result['license'] = values['license'] unless values['license'].to_s.empty?

        supported_by = values['supported_by'].to_s
        result['supported_by'] = supported_by.empty? ? config[:supported_by] : supported_by
        result
      end

      # --- HTML to Markdown ----------------------------------------------------

      def md_block(node, base_url)
        case node.name
        when 'p'      then md_inline(node, base_url)
        when 'ul', 'ol' then md_list(node, base_url)
        when 'table'  then md_table(node, base_url)
        when 'img'    then md_image(node, base_url)
        when 'div'    then node.element_children.map { |child| md_block(child, base_url) }.reject(&:empty?).join("\n\n")
        else               md_inline(node, base_url)
        end
      end

      def md_inline(node, base_url)
        node.children.map { |child| md_inline_node(child, base_url) }.join
      end

      def md_inline_node(node, base_url)
        return node.text.gsub(/\s+/, ' ') if node.text?
        case node.name
        when 'a'
          label = md_inline(node, base_url)
          href  = absolute_url(node['href'].to_s, base_url)
          href.empty? || label.empty? ? label : "[#{label}](#{href})"
        when 'code'            then "`#{node.text.strip}`"
        when 'strong', 'b'     then "**#{md_inline(node, base_url)}**"
        when 'em', 'i'         then "*#{md_inline(node, base_url)}*"
        when 'br'              then "  \n"
        when 'img'             then md_image(node, base_url)
        when 'script', 'style' then ''
        else md_inline(node, base_url)
        end
      end

      def md_image(node, base_url)
        src = absolute_url(node['src'].to_s, base_url)
        src.empty? ? '' : "![#{node['alt']}](#{src})"
      end

      def md_list(node, base_url, indent = '')
        ordered = node.name == 'ol'
        index   = 0
        node.element_children.select { |child| child.name == 'li' }.map do |item|
          index += 1
          sublists = item.element_children.select { |child| %w[ul ol].include?(child.name) }
          content  = item.children.reject { |child| child.element? && %w[ul ol].include?(child.name) }
                       .map { |child| child.text? ? child.text.gsub(/\s+/, ' ').strip : md_inline(child, base_url) }
                       .join.strip
          line = "#{indent}#{ordered ? "#{index}." : '-'} #{content}".rstrip
          line += "\n#{sublists.map { |sub| md_list(sub, base_url, "#{indent}  ") }.join("\n")}" if sublists.any?
          line
        end.join("\n")
      end

      def md_table(node, base_url)
        rows = node.css('tr').map do |row|
          row.element_children.select { |cell| %w[td th].include?(cell.name) }
             .map { |cell| md_inline(cell, base_url).gsub('|', '\\|').gsub(/\s*\n\s*/, ' ').strip }
        end
        return '' if rows.empty?

        width = rows.map(&:size).max
        rows  = rows.map { |row| row + Array.new(width - row.size, '') }
        head  = rows.shift
        ([md_table_row(head), "|#{Array.new(width, '---').join('|')}|"] +
          rows.map { |row| md_table_row(row) }).join("\n")
      end

      def md_table_row(cells)
        cells.empty? ? '' : "| #{cells.join(' | ')} |"
      end

      def start_section(page, id, heading)
        return nil if id.nil? || !SECTIONS.include?(id) || page[:sections].key?(id)
        page[:sections][id] = { :id => id, :heading => heading, :blocks => [] }
      end

      def feature_rows(table)
        table.css('tr').each_with_object({}) do |row, rows|
          cells = row.element_children.select { |cell| %w[td th].include?(cell.name) }
          next if cells.size < 2
          key = attribute_key(cells[0].text)
          next if key.nil? || rows.key?(key)
          rows[key] = cells[1].text.gsub(/\s+/, ' ').strip
        end
      end

      def attribute_key(label)
        label = label.to_s.strip
        ATTRIBUTE_ROWS.each do |key, names|
          return key if names.values.flatten.any? { |name| name.casecmp?(label) }
        end
        nil
      end

      def heading_text(heading)
        return nil if heading.nil?
        node = heading.dup
        node.css('a.headerlink, span.headerlink').remove
        node.text.gsub(/\s+/, ' ').strip
      end

      def absolute_url(href, base_url)
        return href if href.empty? || href.start_with?('#') || href.start_with?('mailto:')
        URI.join(base_url, href).to_s
      rescue URI::Error
        href
      end

      def log(message)
        puts message
      end

      def fetch_site_pages(catalog)
        cfg      = config
        lang     = cfg[:languages].first
        folder   = "#{cfg[:base_url]}/#{lang}/#{catalog_docs_path(catalog)}/"
        nav_url  = nav_source_url(folder)
        pages    = catalog_page_urls(nav_url, folder, catalog)
        log "Catalog [#{catalog}]: #{pages.size} pages, navigation from [#{nav_url}]"
        pages
      rescue StandardError => e
        log "Error: can not read the catalog [#{catalog}] #{e.class}: #{e.message}"
        log "Check the network access to #{cfg[:base_url]}."
        []
      end

      def nav_source_url(folder)
        url = "#{folder}index.html"
        return url if folder_page?(url)

        fallback = url.sub(%r{/[^/]+/index\.html\z}, "/distributions/index.html")
        log "No index page for [#{url}], using [#{fallback}]"
        fallback
      end

      def folder_page?(url)
        http_get(url)
        true
      rescue StandardError
        false
      end

      def catalog_page_urls(nav_url, folder, catalog)
        Nokogiri::HTML(http_get(nav_url))
          .css('nav a.md-nav__link')
          .map { |link| absolute_url(link['href'].to_s, nav_url) }
          .uniq
          .select { |url| image_page?(url, folder, catalog) }
          .sort
      end

      def image_page?(url, folder, catalog)
        return false unless url.start_with?(folder)

        segments = url.delete_prefix(folder).split('/').reject(&:empty?)
        segments.size == catalog_segments(catalog)
      end

      def parse_page(url)
        doc  = Nokogiri::HTML(http_get(url))
        root = doc.at_css('article.md-content__inner') || doc.at_css('div.md-typeset')
        return nil if root.nil?

        page = { :title => heading_text(root.at_css('h1')), :sections => {}, :features => {} }
        section = nil
        root.children.each do |node|
          next unless node.element?
          if node.name.match?(/^h[1-6]$/)
            section = start_section(page, node['id'].to_s, heading_text(node))
          elsif section
            section[:blocks] << md_block(node, url)
            page[:features].merge!(feature_rows(node)) if section[:id] == 'features' && node.name == 'table'
          end
        end
        page
      end

      def http_get(url)
        uri  = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port, nil)
        http.use_ssl      = uri.scheme == 'https'
        http.open_timeout = 15
        http.read_timeout = 30
        response = http.request(Net::HTTP::Get.new(uri.request_uri))
        return response.body if response.is_a?(Net::HTTPSuccess)
        raise "HTTP #{response.code} for #{url}"
      end
    end
  end
end

namespace :platform do
  namespace :images do
    desc 'Sync image descriptions and attributes from the image documentation'
    task :sync_desc => :environment do
      Platform::Images.sync
    end
  end
end

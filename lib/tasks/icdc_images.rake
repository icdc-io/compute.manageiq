require 'nokogiri'
require 'open-uri'

namespace :icdc do
  namespace :images do
    task :sync_desc => :environment do
      page_urls = []
      dir_urls = Queue.new
      dir_urls << "https://help.icdc.io/compute/en/Service_Catalog/Distributions/"
      until dir_urls.empty? # Recursive dir walk-through
        dir_url = dir_urls.pop
        doc = Nokogiri::HTML(URI.parse(dir_url).open)
        doc.xpath("//a").map do |link|
          next if link['href'].starts_with?("/")
          next if link['href'].starts_with?("..")

          page_urls << dir_url + Pathname.new(link['href']).cleanpath.to_s if link['href'].ends_with?(".html")
          dir_urls << dir_url + Pathname.new(link['href']).cleanpath.to_s + "/" if link['href'].ends_with?("/")
        end
      end
      images = {}
      ServiceTemplate.in_my_region.where(display: true).each do |st|
        images[st.name] = {}
        name, version, _location = st.name.split(":", 3)
        version = "" if version == "default"
        next unless st.service_template_catalog

        begin
          set1 = ["VDI Windows 7", "Metrics", "for IBM"].to_set
          set2 = ["Windows"].to_set
          st.miq_custom_set("adm_account", "Administrator") if set2.any? { |x| st.name.include?(x)} && !set1.any? { |x| st.name.include?(x)}
          st.miq_custom_set("adm_account", "root/admin") unless set1.any? { |x| st.name.include?(x)} || set2.any? { |x| st.name.include?(x)}
          st.miq_custom_set("adm_account", "user") if set1.any? { |x| st.name.include?(x)}
        rescue StandardError => e
          open('/var/www/miq/vmdb/log/catalog.log', 'a+'){ |f|   
          f.puts "----------------------------------------------------------"
          f.puts "cannot set custom attribute for #{st.name}:#{e.message}"         
          }
        end

        catalog = st.service_template_catalog.name
        image_help_url = {}
        # Go through pages
        page_urls.each do |url|
          full_match = true
          "#{catalog} #{name} #{version}".downcase.split(/[\s\-]/).each do |word| # Windows:8.1 Pro:NB5
            full_match = false unless url.downcase.include?(word)
          end
          next unless full_match
          next if image_help_url[:en] && image_help_url[:en].length < url.length # shorter candidate wins

          image_help_url[:en] = url
        end
        unless image_help_url[:en]
          p "Error: could not find help page for image [#{st.id}]: #{st.name}"
          next
        end
        # Make links multi-language
        image_help_url[:ru] = image_help_url[:en].gsub('/en/', '/ru/')
        # Update image description
        data = {}
        desc = {}
        table_keys = {
          :licence      => { :en => "License", :ru => "Лицензия" },
          :os           => { :en => "Operating System", :ru => "Операционная система" },
          :supported_by => { :en => "Supported By", :ru => "Поддерживается" }
        }
        image_help_url.each do |lang, url|
          data[lang] = {}
          begin
            doc = Nokogiri::HTML(URI.parse(url).open)
            desc[lang] = doc.at("h3[@id='page_section_1'] ~ *")&.text
            table_keys.each do |key, i10n_keys|
              data[lang][key] = doc.at("td[text()='#{i10n_keys[lang]}'] ~ *")&.text
            end
            data[lang][:doc] = url
          rescue StandardError => e
            p "Error: Can not parse page [#{url}] #{e.message}"
          end
        end
        desc.each { |lang, value| desc[lang] = value || desc[:en] || "" } # if i10n desc is not defined use english description
        # FIX: was not implemented in new catalog
        desc = desc[:en]
        st.long_description = desc # .to_json
        st.save!
        # Additional attributes saved in custom_attributes
        data[:en][:supported_by] = "ICDC" unless data[:en][:supported_by]
        data[:en].keys.each do |key|
          st.miq_custom_set(key.to_s, data[:en][key]) if data[:en][key]
        end
      end
    end
  end
end

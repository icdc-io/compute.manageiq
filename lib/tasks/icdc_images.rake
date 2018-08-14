require 'nokogiri'
require 'open-uri'

namespace :icdc do
  namespace :images do

    @data = {
        linux: {
            search_on: "https://help.icdc.io/en/Service_Catalog/Linux_OS/",
            search_str: "//help.icdc.io/en/Service_Catalog/Linux_OS/"
        },
        windows: {
            search_on: "https://help.icdc.io/en/Service_Catalog/Windows_OS",
            search_str: "//help.icdc.io/en/Service_Catalog/Windows_OS/"
        },
        turnkey: {
            search_on: "https://help.icdc.io/en/Service_Catalog/Turnkey/Turnkey_Services_Access",
            search_str: "//help.icdc.io/en/Service_Catalog/Turnkey/"
        },
        esxi: {
            search_on: "https://help.icdc.io/en/Service_Catalog/Nested-Virtualization",
            search_str: "//help.icdc.io/en/Service_Catalog/Nested-Virtualization/"
        },
        apps: {
            search_on: "https://help.icdc.io/en/Service_Catalog/Apps",
            search_str: "//help.icdc.io/en/Service_Catalog/Apps/"
        },
        special: {
            search_on: "https://help.icdc.io/en/Service_Catalog/Special",
            search_str: "//help.icdc.io/en/Service_Catalog/Special/"
        }
    }

    desc "update images description, source: 'https://help.icdc.io/'"
    task :update_description => :environment do

      @grouped_images = Hash.new

      @data.each do |category, info|
        doc = Nokogiri::HTML(open(info[:search_on]))
        @grouped_images[category] = doc.xpath("//a[starts-with(@href, '#{info[:search_str]}')]").map do |image_tag|
            {
              href: image_tag['href'],
              name: image_tag.text
            }
          end
      end

      @grouped_images.each do |category, images|
        puts
        puts(category.to_s)
        puts

        images.each do |image_data|
          image = ServiceTemplate.find_by(name: image_data[:name])
          next if image.nil?

          desc_en_page = "https:#{image_data[:href]}"
          desc_ru_page = desc_en_page.gsub('/en/', '/ru/')
          begin
            image_en_doc = Nokogiri::HTML(open(desc_en_page))
            en_description = image_en_doc.at("h3[@id='page_Description'] ~ *").text
            en_description << "\n<a href='#{desc_en_page}' target='_blank'>Learn More</a>"

            image_ru_doc = Nokogiri::HTML(open(desc_ru_page))
            ru_description = image_ru_doc.at("h3:contains('Описание') ~ *").text
            ru_description << "\n<a href='#{desc_ru_page}' target='_blank'>Узнать больше</a>"

            long_description = {
                eng: en_description,
                ru: ru_description
            }

            puts("#{image.name} description updated")
            image.update_attribute(:long_description, long_description.to_json)
          rescue => e
            puts("can't update #{image.name}, #{desc_en_page}, #{desc_ru_page}")
          end
        end
      end
    end

  end
end
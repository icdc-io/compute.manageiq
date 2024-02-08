module TaskHelpers
  class Exports
    class CustomButtons
      class ExportArInstances
        EXCLUDE_ATTRS = %w(id created_on updated_on created_at updated_at dialog_id resource_id).freeze
        def self.export_object(obj, hash)
          class_name = obj.class.name.underscore

          $log.info("Exporting #{obj.class.name}: #{obj.try('name')} (ID: #{obj&.id})")
          (hash[class_name] ||= []) << item = { 'attributes' => build_attr_list(obj.try(:attributes)) }
          create_association_list(obj, item)
          descendant_list(obj, item)
        end

        def self.build_attr_list(attrs)
          outp = attrs&.except(*EXCLUDE_ATTRS)
          return outp unless (dialog_id = attrs&.dig('dialog_id'))

          dialog = Dialog.find_by(:id => dialog_id)
          outp.merge('dialog_name' => dialog.name)
        end

        def self.create_association_list(obj, item)
          associations = obj.class.try(:reflections)
          if associations
            associations = associations.collect { |model, assoc| { model => assoc.class.to_s.demodulize } }.select { |as| as.values.first != "BelongsToReflection" && as.keys.first != "all_relationships" }
            associations.each do |assoc|
              assoc.each do |a|
                next if obj.try(a.first.to_sym).blank?

                export_object(obj.try(a.first.to_sym), (item['associations'] ||= {}))
              end
            end
          end
        end

        def self.descendant_list(obj, item)
          obj.try(:children)&.each { |c| export_object(c, (item['children'] ||= {})) }
        end
      end

      def export(options = {})
        export_dir = options[:directory]
        objects = options[:domain] ? CustomButtonSet.where("name LIKE '#{options[:domain]}|%'") : CustomButtonSet.all
        objects = objects.reject { |cbs| cbs.set_data[:applies_to_class].in?(["ServiceTemplate", "GenericObject", nil]) }

        objects.each do |obj|
          export_hash = {}
          $log.info("Exporting Custom Button Set: #{obj.name} (ID: #{obj.id})")
          ExportArInstances.export_object(obj, export_hash)
          filename = Exports.safe_filename(obj.name.chop.tr('|', '-'), options[:keep_spaces])
          File.write("#{export_dir}/#{filename}.yaml", YAML.dump(export_hash))
        end
      end
    end
  end
end

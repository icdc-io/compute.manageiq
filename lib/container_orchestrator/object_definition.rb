class ContainerOrchestrator
  module ObjectDefinition
    private

     def deployment_definition(name)
      {
        :metadata => {
          :name            => name,
          :labels          => common_labels,
          :namespace       => my_namespace,
          :ownerReferences => owner_references
        },
        :spec     => { 
          :selector => {:matchLabels => {:name => name}},
          :template => { 
            :metadata => {:name => name, :labels => common_labels.merge(:name => name)},
            :spec     => {
              :serviceAccountName => ENV["WORKER_SERVICE_ACCOUNT"],
              :volumes            => [{
                :name          => "filebeat",
                :configMap     => {
                  :name      => "filebeat"
                }
              },
              {
                :name => "ssh-volume",
                :emptyDir => {}
              }],
              :containers         => [{
                :name          => name,
                :env           => default_environment,
                :imagePullPolicy => "Always",
                :livenessProbe => liveness_probe,
                :volumeMounts  => [{
                  :name      => "filebeat",
                  :mountPath => "/etc/filebeat",
                  :readOnly  => true
                },
                {
                  :name      => "ssh-volume",
                  :mountPath => "/.ssh",
                  :readOnly  => false
                }]
              }]
            }
          }
        }
      }
    end

    def service_definition(name, selector, port)
      {
        :metadata => {
          :name            => name,
          :labels          => common_labels,
          :namespace       => my_namespace,
          :ownerReferences => owner_references
        },
        :spec     => {
          :selector => selector,
          :ports    => [{
            :name       => "#{name}-#{port}",
            :port       => port,
            :targetPort => port
          }]
        }
      }
    end

    def secret_definition(name, string_data)
      {
        :metadata   => {
          :name            => name,
          :labels          => common_labels,
          :namespace       => my_namespace,
          :ownerReferences => owner_references
        },
        :stringData => string_data
      }
    end

    def default_environment
      [
        {:name => "DATABASE_PORT",           :value => ENV["DATABASE_PORT"]},
        {:name => "GUID",                    :value => MiqServer.my_guid},
        {:name => "MEMCACHED_SERVER",        :value => ENV["MEMCACHED_SERVER"]},
        {:name => "MEMCACHED_SERVICE_NAME",  :value => ENV["MEMCACHED_SERVICE_NAME"]},
        {:name => "WORKER_HEARTBEAT_FILE",   :value => Rails.root.join("tmp", "worker.hb").to_s},
        {:name => "WORKER_HEARTBEAT_METHOD", :value => "file"},
        {:name => "RAILS_ENV",               :value => ENV["WORKERS_ENV"]},
        {:name => "LOCATION_CODE",           :value => ENV["LOCATION_CODE"]},
        {:name => "LOCATION_NAME",           :value => ENV["LOCATION_NAME"]},
        {:name => "LOC_DESCRIPTION",         :value => ENV["LOC_DESCRIPTION"]},
        {:name => "CPV_NAME",                :value => ENV["CPV_NAME"]},
        {:name => "CPV_DOMAIN",              :value => ENV["CPV_DOMAIN"]},
        {:name => "CPV_CLOUD",               :value => ENV["CPV_CLOUD"]},
        {:name => "DNS_SERVER",              :value => ENV["DNS_SERVER"]},
        #{:name => "BUNDLE_PATH",             :value => ENV["BUNDLE_PATH"]},
        {:name => "LOCATION_DOMAIN",         :value => ENV["LOCATION_DOMAIN"]},
        {:name      => "DATABASE_HOSTNAME",
         :valueFrom => {:secretKeyRef=>{:name => "postgresql-secrets", :key => "hostname"}}},
        {:name      => "DATABASE_NAME",
         :valueFrom => {:secretKeyRef=>{:name => "postgresql-secrets", :key => "dbname"}}},
        {:name      => "DATABASE_PASSWORD",
         :valueFrom => {:secretKeyRef=>{:name => "postgresql-secrets", :key => "password"}}},
        {:name      => "DATABASE_USER",
         :valueFrom => {:secretKeyRef=>{:name => "postgresql-secrets", :key => "username"}}},
        {:name      => "DATABASE_URL",
         :valueFrom => {:secretKeyRef=>{:name => "postgresql-secrets", :key => "dburl"}}},
        {:name      => "ENCRYPTION_KEY",
         :valueFrom => {:secretKeyRef=>{:name => "app-secrets", :key => "encryption-key"}}}
      ] + messaging_environment
    end

    def messaging_environment
      return [] unless ENV["MESSAGING_TYPE"].present?

      [
        {:name => "MESSAGING_PORT", :value => ENV["MESSAGING_PORT"]},
        {:name => "MESSAGING_TYPE", :value => ENV["MESSAGING_TYPE"]},
        {:name      => "MESSAGING_HOSTNAME",
         :valueFrom => {:secretKeyRef=>{:name => "kafka-secrets", :key => "hostname"}}},
        {:name      => "MESSAGING_PASSWORD",
         :valueFrom => {:secretKeyRef=>{:name => "kafka-secrets", :key => "password"}}},
        {:name      => "MESSAGING_USERNAME",
         :valueFrom => {:secretKeyRef=>{:name => "kafka-secrets", :key => "username"}}}
      ]
    end

    def liveness_probe
      {
        :exec                => {:command => ["/usr/local/bin/manageiq_liveness_check"]},
        :initialDelaySeconds => 240,
        :timeoutSeconds      => 10,
        :periodSeconds       => 15
      }
    end

    NAMESPACE_FILE = "/run/secrets/kubernetes.io/serviceaccount/namespace".freeze
    def my_namespace
      @my_namespace ||= File.read(NAMESPACE_FILE)
    end

    def app_name
      ENV["APP_NAME"]
    end
 
    def app_name_label
      {:app => app_name}
    end

    def app_name_selector
      "app=#{app_name}"
    end

    def common_labels
      app_name_label.merge(orchestrated_by_label, resource_group_label)
    end

    def resource_group_label
      {:"app.kubernetes.io/part-of" => app_name}
    end

    def orchestrated_by_label
      {:"#{app_name}-orchestrated-by" => pod_name}
    end

    def orchestrated_by_selector
      "#{app_name}-orchestrated-by=#{pod_name}"
    end

    def owner_references
      [{
        :apiVersion         => "v1",
        :blockOwnerDeletion => true,
        :controller         => true,
        :kind               => "Pod",
        :name               => pod_name,
        :uid                => pod_uid
      }]
    end

    def pod_name
      ENV['POD_NAME']
    end

    def pod_uid
      ENV["POD_UID"]
    end
  end
end

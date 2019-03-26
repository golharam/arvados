# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

class Arvados::V1::SchemaController < ApplicationController
  skip_before_action :catch_redirect_hint
  skip_before_action :find_objects_for_index
  skip_before_action :find_object_by_uuid
  skip_before_action :load_filters_param
  skip_before_action :load_limit_offset_order_params
  skip_before_action :load_read_auths
  skip_before_action :load_where_param
  skip_before_action :render_404_if_no_object
  skip_before_action :require_auth_scope

  include DbCurrentTime

  def index
    expires_in 24.hours, public: true
    send_json discovery_doc
  end

  protected

  def discovery_doc
    Rails.cache.fetch 'arvados_v1_rest_discovery' do
      Rails.application.eager_load!
      discovery = {
        kind: "discovery#restDescription",
        discoveryVersion: "v1",
        id: "arvados:v1",
        name: "arvados",
        version: "v1",
        revision: "20131114",
        source_version: AppVersion.hash,
        sourceVersion: AppVersion.hash, # source_version should be deprecated in the future
        packageVersion: AppVersion.package_version,
        generatedAt: db_current_time.iso8601,
        title: "Arvados API",
        description: "The API to interact with Arvados.",
        documentationLink: "http://doc.arvados.org/api/index.html",
        defaultCollectionReplication: Rails.configuration.Collections["DefaultReplication"],
        protocol: "rest",
        baseUrl: root_url + "arvados/v1/",
        basePath: "/arvados/v1/",
        rootUrl: root_url,
        servicePath: "arvados/v1/",
        batchPath: "batch",
        uuidPrefix: Rails.configuration.ClusterID,
        defaultTrashLifetime: Rails.configuration.Collections["DefaultTrashLifetime"],
        blobSignatureTtl: Rails.configuration.Collections["BlobSigningTTL"],
        maxRequestSize: Rails.configuration.API["MaxRequestSize"],
        maxItemsPerResponse: Rails.configuration.API["MaxItemsPerResponse"],
        dockerImageFormats: Rails.configuration.Containers["SupportedDockerImageFormats"],
        crunchLogBytesPerEvent: Rails.configuration.Containers["Logging"]["LogBytesPerEvent"],
        crunchLogSecondsBetweenEvents: Rails.configuration.Containers["Logging"]["LogSecondsBetweenEvents"],
        crunchLogThrottlePeriod: Rails.configuration.Containers["Logging"]["LogThrottlePeriod"],
        crunchLogThrottleBytes: Rails.configuration.Containers["Logging"]["LogThrottleBytes"],
        crunchLogThrottleLines: Rails.configuration.Containers["Logging"]["LogThrottleLines"],
        crunchLimitLogBytesPerJob: Rails.configuration.Containers["Logging"]["LimitLogBytesPerJob"],
        crunchLogPartialLineThrottlePeriod: Rails.configuration.Containers["Logging"]["LogPartialLineThrottlePeriod"],
        crunchLogUpdatePeriod: Rails.configuration.Containers["Logging"]["LogUpdatePeriod"],
        crunchLogUpdateSize: Rails.configuration.Containers["Logging"]["LogUpdateSize"],
        remoteHosts: Rails.configuration.RemoteClusters.map {|k,v| v["Host"]},
        remoteHostsViaDNS: Rails.configuration.RemoteClusters["*"]["Proxy"],
        websocketUrl: Rails.configuration.Services["Websocket"]["ExternalURL"].to_s,
        workbenchUrl: Rails.configuration.Services["Workbench1"]["ExternalURL"].to_s,
        keepWebServiceUrl: Rails.configuration.Services["WebDAV"]["ExternalURL"].to_s,
        gitUrl: Rails.configuration.Services["GitHTTP"]["ExternalURL"].to_s,
        parameters: {
          alt: {
            type: "string",
            description: "Data format for the response.",
            default: "json",
            enum: [
                   "json"
                  ],
            enumDescriptions: [
                               "Responses with Content-Type of application/json"
                              ],
            location: "query"
          },
          fields: {
            type: "string",
            description: "Selector specifying which fields to include in a partial response.",
            location: "query"
          },
          key: {
            type: "string",
            description: "API key. Your API key identifies your project and provides you with API access, quota, and reports. Required unless you provide an OAuth 2.0 token.",
            location: "query"
          },
          oauth_token: {
            type: "string",
            description: "OAuth 2.0 token for the current user.",
            location: "query"
          }
        },
        auth: {
          oauth2: {
            scopes: {
              "https://api.curoverse.com/auth/arvados" => {
                description: "View and manage objects"
              },
              "https://api.curoverse.com/auth/arvados.readonly" => {
                description: "View objects"
              }
            }
          }
        },
        schemas: {},
        resources: {}
      }

      ActiveRecord::Base.descendants.reject(&:abstract_class?).each do |k|
        begin
          ctl_class = "Arvados::V1::#{k.to_s.pluralize}Controller".constantize
        rescue
          # No controller -> no discovery.
          next
        end
        object_properties = {}
        k.columns.
          select { |col| col.name != 'id' && !col.name.start_with?('secret_') }.
          collect do |col|
          if k.serialized_attributes.has_key? col.name
            object_properties[col.name] = {
              type: k.serialized_attributes[col.name].object_class.to_s
            }
          elsif k.attribute_types[col.name].is_a? JsonbType::Hash
            object_properties[col.name] = {
              type: Hash.to_s
            }
          elsif k.attribute_types[col.name].is_a? JsonbType::Array
            object_properties[col.name] = {
              type: Array.to_s
            }
          else
            object_properties[col.name] = {
              type: col.type
            }
          end
        end
        discovery[:schemas][k.to_s + 'List'] = {
          id: k.to_s + 'List',
          description: k.to_s + ' list',
          type: "object",
          properties: {
            kind: {
              type: "string",
              description: "Object type. Always arvados##{k.to_s.camelcase(:lower)}List.",
              default: "arvados##{k.to_s.camelcase(:lower)}List"
            },
            etag: {
              type: "string",
              description: "List version."
            },
            items: {
              type: "array",
              description: "The list of #{k.to_s.pluralize}.",
              items: {
                "$ref" => k.to_s
              }
            },
            next_link: {
              type: "string",
              description: "A link to the next page of #{k.to_s.pluralize}."
            },
            next_page_token: {
              type: "string",
              description: "The page token for the next page of #{k.to_s.pluralize}."
            },
            selfLink: {
              type: "string",
              description: "A link back to this list."
            }
          }
        }
        discovery[:schemas][k.to_s] = {
          id: k.to_s,
          description: k.to_s,
          type: "object",
          uuidPrefix: (k.respond_to?(:uuid_prefix) ? k.uuid_prefix : nil),
          properties: {
            uuid: {
              type: "string",
              description: "Object ID."
            },
            etag: {
              type: "string",
              description: "Object version."
            }
          }.merge(object_properties)
        }
        discovery[:resources][k.to_s.underscore.pluralize] = {
          methods: {
            get: {
              id: "arvados.#{k.to_s.underscore.pluralize}.get",
              path: "#{k.to_s.underscore.pluralize}/{uuid}",
              httpMethod: "GET",
              description: "Gets a #{k.to_s}'s metadata by UUID.",
              parameters: {
                uuid: {
                  type: "string",
                  description: "The UUID of the #{k.to_s} in question.",
                  required: true,
                  location: "path"
                }
              },
              parameterOrder: [
                               "uuid"
                              ],
              response: {
                "$ref" => k.to_s
              },
              scopes: [
                       "https://api.curoverse.com/auth/arvados",
                       "https://api.curoverse.com/auth/arvados.readonly"
                      ]
            },
            index: {
              id: "arvados.#{k.to_s.underscore.pluralize}.index",
              path: k.to_s.underscore.pluralize,
              httpMethod: "GET",
              description:
                 %|Index #{k.to_s.pluralize}.

                   The <code>index</code> method returns a
                   <a href="/api/resources.html">resource list</a> of
                   matching #{k.to_s.pluralize}. For example:

                   <pre>
                   {
                    "kind":"arvados##{k.to_s.camelcase(:lower)}List",
                    "etag":"",
                    "self_link":"",
                    "next_page_token":"",
                    "next_link":"",
                    "items":[
                       ...
                    ],
                    "items_available":745,
                    "_profile":{
                     "request_time":0.157236317
                    }
                    </pre>|,
              parameters: {
              },
              response: {
                "$ref" => "#{k.to_s}List"
              },
              scopes: [
                       "https://api.curoverse.com/auth/arvados",
                       "https://api.curoverse.com/auth/arvados.readonly"
                      ]
            },
            create: {
              id: "arvados.#{k.to_s.underscore.pluralize}.create",
              path: "#{k.to_s.underscore.pluralize}",
              httpMethod: "POST",
              description: "Create a new #{k.to_s}.",
              parameters: {},
              request: {
                required: true,
                properties: {
                  k.to_s.underscore => {
                    "$ref" => k.to_s
                  }
                }
              },
              response: {
                "$ref" => k.to_s
              },
              scopes: [
                       "https://api.curoverse.com/auth/arvados"
                      ]
            },
            update: {
              id: "arvados.#{k.to_s.underscore.pluralize}.update",
              path: "#{k.to_s.underscore.pluralize}/{uuid}",
              httpMethod: "PUT",
              description: "Update attributes of an existing #{k.to_s}.",
              parameters: {
                uuid: {
                  type: "string",
                  description: "The UUID of the #{k.to_s} in question.",
                  required: true,
                  location: "path"
                }
              },
              request: {
                required: true,
                properties: {
                  k.to_s.underscore => {
                    "$ref" => k.to_s
                  }
                }
              },
              response: {
                "$ref" => k.to_s
              },
              scopes: [
                       "https://api.curoverse.com/auth/arvados"
                      ]
            },
            delete: {
              id: "arvados.#{k.to_s.underscore.pluralize}.delete",
              path: "#{k.to_s.underscore.pluralize}/{uuid}",
              httpMethod: "DELETE",
              description: "Delete an existing #{k.to_s}.",
              parameters: {
                uuid: {
                  type: "string",
                  description: "The UUID of the #{k.to_s} in question.",
                  required: true,
                  location: "path"
                }
              },
              response: {
                "$ref" => k.to_s
              },
              scopes: [
                       "https://api.curoverse.com/auth/arvados"
                      ]
            }
          }
        }
        # Check for Rails routes that don't match the usual actions
        # listed above
        d_methods = discovery[:resources][k.to_s.underscore.pluralize][:methods]
        Rails.application.routes.routes.each do |route|
          action = route.defaults[:action]
          httpMethod = ['GET', 'POST', 'PUT', 'DELETE'].map { |method|
            method if route.verb.match(method)
          }.compact.first
          if httpMethod and
              route.defaults[:controller] == 'arvados/v1/' + k.to_s.underscore.pluralize and
              ctl_class.action_methods.include? action
            if !d_methods[action.to_sym]
              method = {
                id: "arvados.#{k.to_s.underscore.pluralize}.#{action}",
                path: route.path.spec.to_s.sub('/arvados/v1/','').sub('(.:format)','').sub(/:(uu)?id/,'{uuid}'),
                httpMethod: httpMethod,
                description: "#{action} #{k.to_s.underscore.pluralize}",
                parameters: {},
                response: {
                  "$ref" => (action == 'index' ? "#{k.to_s}List" : k.to_s)
                },
                scopes: [
                         "https://api.curoverse.com/auth/arvados"
                        ]
              }
              route.segment_keys.each do |key|
                if key != :format
                  key = :uuid if key == :id
                  method[:parameters][key] = {
                    type: "string",
                    description: "",
                    required: true,
                    location: "path"
                  }
                end
              end
            else
              # We already built a generic method description, but we
              # might find some more required parameters through
              # introspection.
              method = d_methods[action.to_sym]
            end
            if ctl_class.respond_to? "_#{action}_requires_parameters".to_sym
              ctl_class.send("_#{action}_requires_parameters".to_sym).each do |l, v|
                if v.is_a? Hash
                  method[:parameters][l] = v
                else
                  method[:parameters][l] = {}
                end
                if !method[:parameters][l][:default].nil?
                  # The JAVA SDK is sensitive to all values being strings
                  method[:parameters][l][:default] = method[:parameters][l][:default].to_s
                end
                method[:parameters][l][:type] ||= 'string'
                method[:parameters][l][:description] ||= ''
                method[:parameters][l][:location] = (route.segment_keys.include?(l) ? 'path' : 'query')
                if method[:parameters][l][:required].nil?
                  method[:parameters][l][:required] = v != false
                end
              end
            end
            d_methods[action.to_sym] = method

            if action == 'index'
              list_method = method.dup
              list_method[:id].sub!('index', 'list')
              list_method[:description].sub!('Index', 'List')
              list_method[:description].sub!('index', 'list')
              d_methods[:list] = list_method
            end
          end
        end
      end
      Rails.configuration.API["DisabledAPIs"].each do |method|
        ctrl, action = method.split('.', 2)
        discovery[:resources][ctrl][:methods].delete(action.to_sym)
      end
      discovery
    end
  end
end

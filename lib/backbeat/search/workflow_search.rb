module Backbeat
  module Search
    class WorkflowSearch
      def self.filter_for(param, &block)
        lambda do |relation, params|
          if params[param]
            block.call(relation, params)
          else
            relation
          end
        end
      end

      def initialize(params)
        @params = params
      end

      def result
        apply_filters(
          NameFilter,
          SubjectFilter,
          CurrentStatusFilter,
          PastStatusFilter,
          StatusStartFilter,
          StatusEndFilter
        )
      end

      NameFilter = filter_for(:name) do |relation, params|
        relation.where("workflows.name = ?", params[:name])
      end

      SubjectFilter = filter_for(:subject) do |relation, params|
        relation.where("workflows.subject LIKE ?", "%#{params[:subject]}%")
      end

      CurrentStatusFilter = filter_for(:current_status) do |relation, params|
        relation.joins(:nodes).where(
          "nodes.current_server_status = ? OR nodes.current_client_status = ?",
          params[:current_status],
          params[:current_status]
        )
      end

      PastStatusFilter = filter_for(:past_status) do |relation, params|
        relation.joins(:nodes).joins("JOIN status_changes ON status_changes.node_id = nodes.id").where(
          "status_changes.to_status = ?",
          params[:past_status]
        )
      end

      StatusStartFilter = filter_for(:status_start) do |relation, params|
        relation.where("status_changes.created_at >= ?", params[:status_start])
      end

      StatusEndFilter = filter_for(:status_end) do |relation, params|
        relation.where("status_changes.created_at <= ?", params[:status_end])
      end

      private

      attr_reader :params

      def apply_filters(*filters)
        return [] if params.empty?
        filters.reduce(Workflow) do |relation, filter|
          filter.call(relation, params)
        end
      end
    end
  end
end

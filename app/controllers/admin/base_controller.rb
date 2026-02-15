module Admin
  class BaseController < ApplicationController
    rescue_from ActiveRecord::RecordNotFound, with: :not_found

    private

    def not_found
      render json: { error: "Not found" }, status: :not_found
    end

    def paginate(scope)
      limit = [ (params[:limit] || 50).to_i, 500 ].min
      offset = [ (params[:offset] || 0).to_i, 0 ].max

      {
        total: scope.count,
        limit: limit,
        offset: offset,
        records: scope.limit(limit).offset(offset)
      }
    end

    def search_filter(scope, columns)
      return scope unless params[:q].present?

      q = "%#{params[:q]}%"
      conditions = columns.map { |col| "#{col} LIKE :q" }.join(" OR ")
      scope.where(conditions, q: q)
    end
  end
end

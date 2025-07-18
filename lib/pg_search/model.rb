# frozen_string_literal: true

module PgSearch
  #此Module用于附着在ActiveRecord上，获得全文搜索能力
  module Model #ActiveSupport简化了静态方法的实现
    extend ActiveSupport::Concern

    module ClassMethods
      # name:调用方给这个搜索起什么名字，将来就会生成同名 类方法
      # options：既可以是 Hash（静态配置），也可以是 Proc（动态运行时拼接）
      def pg_search_scope(name, options)
        # respond_to?方法是用于询问是否有:call(本例)方法，返回true或false
        options_proc = if options.respond_to?(:call)
          options
        elsif options.respond_to?(:merge)
          ->(query) { {query: query}.merge(options) }
        else
          raise ArgumentError, "pg_search_scope expects a Hash or Proc"
        end
        # 动态运行时定义类方法
        define_singleton_method(name) do |*args|
          config = Configuration.new(options_proc.call(*args), self)
          scope_options = ScopeOptions.new(config)
          scope_options.apply(self)
        end
      end

      def multisearchable(options = {})
        include PgSearch::Multisearchable
        class_attribute :pg_search_multisearchable_options
        self.pg_search_multisearchable_options = options
      end
    end

    def method_missing(symbol, *args)
      case symbol
      when :pg_search_rank
        raise PgSearchRankNotSelected unless respond_to?(:pg_search_rank)

        read_attribute(:pg_search_rank).to_f
      when :pg_search_highlight
        raise PgSearchHighlightNotSelected unless respond_to?(:pg_search_highlight)

        read_attribute(:pg_search_highlight)
      else
        super
      end
    end

    def respond_to_missing?(symbol, *args)
      case symbol
      when :pg_search_rank
        attributes.key?(:pg_search_rank)
      when :pg_search_highlight
        attributes.key?(:pg_search_highlight)
      else
        super
      end
    end
  end
end

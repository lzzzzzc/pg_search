# frozen_string_literal: true

module PgSearch
  #此Module用于附着在ActiveRecord上，获得全文搜索能力
  module Model #ActiveSupport简化了静态方法的实现
    extend ActiveSupport::Concern

    module ClassMethods
      # name:调用方给这个搜索起什么名字，将来就会生成同名 类方法
      # options：既可以是 Hash（静态配置），也可以是 Proc（动态运行时拼接）
      # 定义一个名为pg_search_scope的方法，用于创建一个PostgreSQL搜索作用域
      # 该方法接受两个参数：name（作用域的名称）和options（配置选项）
      def pg_search_scope(name, options)
        # 根据options参数的类型（Proc或可合并的Hash），决定如何处理查询参数
        options_proc = if options.respond_to?(:call)
          # 如果options是一个Proc，直接使用它
          # Proc是一个代码块的封装对象
          options
        elsif options.respond_to?(:merge)
          # 如果options是一个Hash，创建一个Proc将查询参数与options合并
          ->(query) { {query: query}.merge(options) }
        else
          # 如果options既不是Proc也不是可合并的Hash，抛出异常
          raise ArgumentError, "pg_search_scope expects a Hash or Proc"
        end
        # 动态运行时定义类方法（创建自己的命名方法）
        define_singleton_method(name) do |*args|
          # 创建并配置一个Configuration实例
          config = Configuration.new(options_proc.call(*args), self)
          # 创建一个ScopeOptions实例，并应用配置
          scope_options = ScopeOptions.new(config)
          # 根据配置应用作用域选项
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

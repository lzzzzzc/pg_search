# frozen_string_literal: true

require "active_support/core_ext/module/delegation"

# PgSearch模块用于在Ruby on Rails应用程序中实现对PostgreSQL的全文搜索功能
# ScopeOptions类负责处理搜索的范围选项，以便在模型中执行搜索查询
module PgSearch
  class ScopeOptions
    # 初始化ScopeOptions类的新实例
    # @param config [Configuration] 搜索的配置选项
    attr_reader :config, :feature_options, :model

    # 初始化方法，设置config，model和feature_options实例变量
    def initialize(config)
      @config = config
      @model = config.model
      @feature_options = config.feature_options
    end

    # 应用搜索范围的方法，包括排名和高亮功能
    # @param scope [ActiveRecord::Relation] 搜索作用的范围
    # @return [ActiveRecord::Relation] 应用了搜索选项的范围
    def apply(scope)
      scope = include_table_aliasing_for_rank(scope)
      rank_table_alias = scope.pg_search_rank_table_alias(include_counter: true)

      scope
        .joins(rank_join(rank_table_alias))
        .order(Arel.sql("#{rank_table_alias}.rank DESC, #{order_within_rank}"))
        .extend(WithPgSearchRank)
        .extend(WithPgSearchHighlight[feature_for(:tsearch)])
    end

    # WithPgSearchHighlight模块用于在搜索结果中添加高亮功能
    module WithPgSearchHighlight
      # 创建一个新的模块实例，包括WithPgSearchHighlight模块并定义tsearch方法
      def self.[](tsearch)
        Module.new do
          include WithPgSearchHighlight
          define_method(:tsearch) { tsearch }
        end
      end

      # tsearch方法的默认实现，需要通过[]方法进行实例化
      def tsearch
        raise TypeError, "You need to instantiate this module with []"
      end

      # 在搜索结果中添加高亮字段
      def with_pg_search_highlight
        scope = self
        scope = scope.select("#{table_name}.*") unless scope.select_values.any?
        scope.select("(#{highlight}) AS pg_search_highlight")
      end

      # 生成高亮的SQL表达式
      def highlight
        tsearch.highlight.to_sql
      end
    end

    # WithPgSearchRank模块用于在搜索结果中添加排名功能
    module WithPgSearchRank
      # 在搜索结果中添加排名字段
      def with_pg_search_rank
        scope = self
        scope = scope.select("#{table_name}.*") unless scope.select_values.any?
        scope.select("#{pg_search_rank_table_alias}.rank AS pg_search_rank")
      end
    end

    # PgSearchRankTableAliasing模块用于处理排名表的别名生成
    module PgSearchRankTableAliasing
      # 生成排名表的别名
      # @param include_counter [Boolean] 是否包括计数器
      # @return [String] 生成的别名
      def pg_search_rank_table_alias(include_counter: false)
        components = [arel_table.name]
        if include_counter
          count = increment_counter
          components << count if count > 0
        end

        Configuration.alias(components)
      end

      private

      # 增加计数器以支持别名的唯一性
      def increment_counter
        @counter ||= 0
      ensure
        @counter += 1
      end
    end

    private

    # 委托方法，用于访问model的connection和quoted_table_name方法
    delegate :connection, :quoted_table_name, to: :model

    # 生成排名的子查询
    def subquery
      model
        .unscoped
        .select("#{primary_key} AS pg_search_id")
        .select("#{rank} AS rank")
        .joins(subquery_join)
        .where(conditions)
        .limit(nil)
        .offset(nil)
    end

    # 生成搜索条件的SQL表达式
    def conditions
      expressions =
        config.features
          .reject { |_feature_name, feature_options| feature_options && feature_options[:sort_only] }
          .map { |feature_name, _feature_options| feature_for(feature_name).conditions }

      or_node(expressions)
    end

    # 根据Arel::Nodes::Or的参数数量选择合适的or_node方法
    or_arity = Arel::Nodes::Or.instance_method(:initialize).arity
    case or_arity
    when 1
      def or_node(expressions)
        Arel::Nodes::Or.new(expressions)
      end
    when 2
      def or_node(expressions)
        expressions.inject { |accumulator, expression| Arel::Nodes::Or.new(accumulator, expression) }
      end
    else
      raise "Unsupported arity #{or_arity} for Arel::Nodes::Or#initialize"
    end

    # 生成排序的SQL表达式
    def order_within_rank
      config.order_within_rank || "#{primary_key} ASC"
    end

    # 生成主键的SQL表达式
    def primary_key
      "#{quoted_table_name}.#{connection.quote_column_name(model.primary_key)}"
    end

    # 生成子查询的连接条件
    def subquery_join
      if config.associations.any?
        config.associations.map do |association|
          association.join(primary_key)
        end.join(" ")
      end
    end

    # 包含特征类的常量定义
    FEATURE_CLASSES = {
      dmetaphone: Features::DMetaphone,
      tsearch: Features::TSearch,
      trigram: Features::Trigram
    }.freeze

    # 根据特征名称创建特征实例
    def feature_for(feature_name)
      feature_name = feature_name.to_sym
      feature_class = FEATURE_CLASSES[feature_name]

      raise ArgumentError, "Unknown feature: #{feature_name}" unless feature_class

      normalizer = Normalizer.new(config)

      feature_class.new(
        config.query,
        feature_options[feature_name],
        config.columns,
        config.model,
        normalizer
      )
    end

    # 生成排名的SQL表达式
    def rank
      (config.ranking_sql || ":tsearch").gsub(/:(\w*)/) do
        feature_for(Regexp.last_match(1)).rank.to_sql
      end
    end

    # 生成排名连接的SQL表达式
    def rank_join(rank_table_alias)
      "INNER JOIN (#{subquery.to_sql}) AS #{rank_table_alias} ON #{primary_key} = #{rank_table_alias}.pg_search_id"
    end

    # 在范围中包括排名表的别名功能
    def include_table_aliasing_for_rank(scope)
      return scope if scope.included_modules.include?(PgSearchRankTableAliasing)

      scope.all.spawn.tap do |new_scope|
        new_scope.instance_eval { extend PgSearchRankTableAliasing }
      end
    end
  end
end

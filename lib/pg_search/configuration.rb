# frozen_string_literal: true

# 引入所需的模块以进行 PgSearch 配置
require "pg_search/configuration/association"
require "pg_search/configuration/column"
require "pg_search/configuration/foreign_column"

# PgSearch 模块命名空间
module PgSearch
  # 配置 PgSearch 行为的类
  class Configuration
    # 获取 model 属性的读取器
    # 需要将外部提取model属性值时，使用这个
    attr_reader :model

    # 初始化一个新的 Configuration 实例
    # 参数:
    # - options: 包含配置选项的哈希
    # - model: 应用配置的模型类
    def initialize(options, model)
      # 默认配置选项为使用tsearch
      @options = default_options.merge(options)
      @model = model

      # 验证配置选项
      assert_valid_options(@options)
    end

    # 类方法，生成唯一的搜索别名名称
    # 参数:
    # - *strings: 生成别名所需的多个字符串参数
    # 返回:
    # - 一个表示唯一别名的字符串
    class << self
      #这个别名用于标识 PgSearch 的特定查询配置，用于在数据库中唯一区分不同的搜索配置。
      def alias(*strings)
        name = Array(strings).compact.join("_")
        # PostgreSQL 默认限制名称为 32 字符，因此我们进行哈希处理并限制为 32 字符
        "pg_search_#{Digest::SHA2.hexdigest(name)}".first(32)
      end
    end

    # 获取所有参与搜索的列，包括关联模型的列
    # 返回:
    # - 由 Column 和 Association 对象组成的数组
    def columns
      regular_columns + associated_columns
    end

    # 获取当前模型中参与搜索的列
    # 返回:
    # - Column 对象的数组
    def regular_columns
      return [] unless options[:against]
      # 方法中最后一个变量就是return的值
      Array(options[:against]).map do |column_name, weight|
        Column.new(column_name, weight, model)
      end
    end

    # 获取参与搜索的关联模型
    # 返回:
    # - Association 对象的数组
    def associations
      return [] unless options[:associated_against]

      options[:associated_against].map do |association, column_names|
        Association.new(model, association, column_names)
      end.flatten
    end

    # 获取关联模型中参与搜索的列
    # 返回:
    # - 关联模型的 Column 对象数组
     def associated_columns
      associations.map(&:columns).flatten
    end

    # 获取搜索查询字符串
    # 返回:
    # - 查询字符串
    def query
      options[:query].to_s
    end

    # 获取忽略的选项
    # 返回:
    # - 忽略选项的数组
    def ignore
      Array(options[:ignoring])
    end

    # 获取排序 SQL 表达式
    # 返回:
    # - 排序 SQL 表达式
    def ranking_sql
      options[:ranked_by]
    end

    # 获取启用的搜索特性
    # 返回:
    # - 使用的特性数组
    def features
      Array(options[:using])
    end

    # 获取每个搜索特性对应的选项
    # 返回:
    # - 特性与选项的哈希表
    def feature_options
      # ||=是懒加载的意思
      @feature_options ||= {}.tap do |hash|
        features.map do |feature_name, feature_options|
          hash[feature_name] = feature_options
        end
      end
    end

    # 获取排序方式
    # 返回:
    # - 排序方式
    def order_within_rank
      options[:order_within_rank]
    end

    private

    # 获取 options 属性的读取器
    attr_reader :options

    # 默认配置选项
    # 返回:
    # - 默认选项哈希
    def default_options
      {using: :tsearch}
    end

    # 标准:disable Lint/UselessConstantScoping
    # 验证的键列表
    VALID_KEYS = %w[
      against ranked_by ignoring using query associated_against order_within_rank
    ].map(&:to_sym)

    # 验证值的定义
    VALID_VALUES = {
      ignoring: [:accents]
    }.freeze
    # 标准:enable Lint/UselessConstantScoping

    # 验证传入的配置选项
    def assert_valid_options(options)
      unless options[:against] || options[:associated_against] || using_tsvector_column?(options[:using])
        raise(
          ArgumentError,
          "the search scope #{@name} must have :against, :associated_against, or :tsvector_column in its options"
        )
      end

      options.assert_valid_keys(VALID_KEYS)

      VALID_VALUES.each do |key, values_for_key|
        Array(options[key]).each do |value|
          raise ArgumentError, ":#{key} cannot accept #{value}" unless values_for_key.include?(value)
        end
      end
    end

    # 检查是否使用了 tsvector 列
    def using_tsvector_column?(options)
      return unless options.is_a?(Hash)

      options.dig(:dmetaphone, :tsvector_column).present? ||
        options.dig(:tsearch, :tsvector_column).present?
    end
  end
end

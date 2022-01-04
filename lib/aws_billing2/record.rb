module AwsBilling2
  class Record
    attr_accessor :key, :val, :original_row, :project, :linked, :product, :usage

    def self.from_csv_row(csv_row, skip_zero: false)
      out = Record.new

      return nil if csv_row['ProductName'].nil?
      return nil if csv_row['TotalCost'].to_s.length.zero?

      total_cost_s = csv_row['TotalCost'].to_s.strip.gsub(/[\r\n]/, '')
      return nil if BigDecimal(total_cost_s).zero? && skip_zero

      out.project      = csv_row['user:Project'].to_s.strip.gsub(/[\r\n]/, '')
      out.linked       = csv_row['LinkedAccountId'].to_s.strip.gsub(/[\r\n]/, '')
      out.product      = csv_row['ProductName'].to_s.strip.gsub(/[\r\n]/, '')
      out.val          = BigDecimal(total_cost_s)
      out.usage        = csv_row['UsageType'].to_s.strip.gsub(/[\r\n]/, '')
      out.original_row = csv_row
      out
    end

    def profit?
      @val.positive?
    end

    def loss?
      !profit?
    end

    def product_with_usage
      "#{@product} (#{@usage})"
    end

    def sort_key
      [@linked, @product, product_with_usage].join(' ')
    end
  end
end
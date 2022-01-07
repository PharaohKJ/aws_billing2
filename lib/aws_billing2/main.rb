# coding: utf-8

module AwsBilling2
  class AwsBilling2
    def nickname(hash)
      @nickname = hash
    end

    def initialize(values)
      @aws_config = {}
      %i[access_key_id secret_access_key region].each do |k|
        @aws_config[k] = values[k.to_s]
      end
      @yen = BigDecimal(values[:ypd.to_s].to_f.to_s)
      @format = values[:format.to_s]
      @total_record = values[:total.to_s]
      @skip_zero_record = values[:skip_zero.to_s]
      @records = []
    end

    def fetch_bucket(bucket: 'bucketname', yearmonth: Time.now.strftime('%Y-%m'), key: nil, invoice_id: 'invoice_id')
      out = []
      key ||= "#{invoice_id}-aws-cost-allocation-#{yearmonth}.csv"
      Aws.config = @aws_config
      Aws::S3::Client.new.get_object(bucket: bucket, key: key) do |chunk|
        out += chunk.split("\n")
      end
      out
    end

    def normalize_record(record_with_header)
      %w[user:Project LinkedAccountId].each do |k|
        record_with_header[k] = 'none' if record_with_header[k].to_s.empty?
      end
      record_with_header.each do |k, v|
        record_with_header[k] = v.to_s.strip
      end
    end

    def take_records(csv)
      @records = []
      csv.each do |l|
        next unless acceptable_line?(l)

        normalize_record(l)
        new_record = Record.from_csv_row(l, skip_zero: @skip_zero_record, nicknames: @nickname)
        @records << new_record
        @records.compact!
      end
    end

    def parse(bucket_value)
      csv = CSV.new(bucket_value[1..-1].join("\n"), headers: true)
      take_records(csv)

      @records.sort! do |a, b|
        r = a.sort_key <=> b.sort_key
        next r unless r.zero?

        next b.val <=> a.val
      end
    end

    def gets_table(format = @format)
      acceptable_values = %w[csv cli json]
      unless acceptable_values.include?(format)
        raise "Unknown format #{format}. Please select below #{acceptable_values}."
      end

      head = ['PayID', 'Tag', 'Item', '$', "Yen(#{@yen.to_i}/$)", '%']
      rows = []

      records = @records
      records = records.reject { |r| r.val.zero? } if @skip_zero_record

      profit_records = records.select(&:profit?)
      profit_total = profit_records.sum(&:val).to_f

      loss_records = records.select(&:loss?)
      loss_total = loss_records.sum(&:val).to_f

      records.each do |r|
        rate = '-'
        unless r.val.zero?
          rate = '%8.3f' % (if r.profit?
                              r.val / profit_total
                            else
                              r.val / loss_total
                            end * 100)
        end
        rows << (
          Array(r.linked) + Array(r.project) + Array(r.product_with_usage) +
            Array('%.5f' % r.val.to_f) +
            Array('%.2f' % (r.val.to_f * @yen)) +
            Array(rate)
        )
      end

      rows << (
        Array('----')  + Array('----') + Array('----') +
          Array('-------') +
          Array('-----') +
          Array('-------------')
      )

      rows << (
        Array('*') + Array('*') + Array('* profit total *') +
          Array('%.5f' % profit_total) +
          Array('%.2f' % (profit_total * @yen)) +
          Array('*')
      )

      rows << (
        Array('*') + Array('*') + Array('* loss total *') +
          Array('%.5f' % loss_total) +
          Array('%.2f' % (loss_total * @yen)) +
          Array('*')
      )



      case format
      when 'json'
        out = []
        rows.each do |r|
          record = {}
          head.each_with_index do |h, i|
            record[h.to_s] = r[i].strip
          end
          out << record
        end
        out.to_json
      when 'csv'
        out = "#{head.join(',')}\n"
        rows.each do |r|
          out += "#{r.join(',')}\n"
        end
        out
      else
        table = Text::Table.new
        table.head = head
        table.rows = rows
        table.align_column 4, :right
        table.align_column 5, :right
        table.align_column 6, :right
        table.to_s
      end
    end

    private

    def acceptable_line?(line)
      return true if line['RecordType'] == 'PayerLineItem' && !line['ProductName'].nil?
      return true if line['RecordType'] == 'LinkedLineItem' && !line['ProductName'].nil?
      return false if line['TotalCost'].nil?

      false
    end
  end
end

# coding: utf-8

module AwsBilling2
  class AwsBilling2
    def nickname(hash)
      @nickname = hash
    end

    def initialize(values)
      @aws_config = {}
      [:access_key_id, :secret_access_key, :region].each do |k|
        @aws_config[k] = values[k.to_s]
      end
      @yen = values[:ypd.to_s].to_f
      @pay = {}
      @payment = {}
      @payment_description = {}
      @format = values[:format.to_s]
      @total_record = values[:total.to_s]
      @skip_zero_record = values[:skip_zero.to_s]
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
      %w(user:Project LinkedAccountId).each do |k|
        record_with_header[k] = 'none' if record_with_header[k].to_s.empty?
      end
      record_with_header.each do |k, v|
        record_with_header[k] = v.to_s.delete("\n")
      end
    end

    def take_records(csv)
      csv.each do |l|
        next unless acceptable_line?(l)
        normalize_record(l)
        project = l['user:Project']
        linked  = l['LinkedAccountId']
        linked = @nickname[linked] unless @nickname[linked].nil?
        hash_key = payment_key(project, linked)
        @pay[hash_key] = Array(@pay[hash_key]) << l
      end
    end

    def append_total(cost, key, description_key)
      cost = cost.to_f
      @payment[key] += cost
      @payment['total'] += cost
      @payment_description[description_key] += cost
    end

    def parse(bucket_value)
      csv = CSV.new(bucket_value[1..-1].join("\n"), headers: true)
      take_records(csv)

      @pay.each do |k, l|
        l.sort! do |a, b|
          a['ProductName'].to_s <=> b['ProductName'].to_s
        end
        l.each do |p|
          next if p['ProductName'].nil?
          next if p['TotalCost'].to_f < 0.00001 && @skip_zero_record == true
          @payment[k] = 0 if @payment[k].nil?
          @payment['total'] = 0 if @payment['total'].nil?
          key = payment_description_key(k, p['ProductName'])
          @payment_description[key] = @payment_description[key] || 0
          append_total(p['TotalCost'], k, key)
        end
      end
    end

    def gets_table(format = @format, with_total_record = @total_record)
      acceptables = %w(csv cli json)
      raise "Unknown format #{format}. Please select below #{acceptables}." unless acceptables.include?(format)

      head = ['PayID', 'Tag', 'Item', '$', "Yen(#{@yen.to_i}/$)", '%']
      rows = []
      @payment_description.each do |k, l|
        rows << (
          Array(k.split(':')) +
          Array('%.5f' % l) +
          Array('%.2f' % (l * @yen)) +
          Array('%8.3f' % (l / @payment['total'] * 100))
        )
      end
      if with_total_record
        total = @payment['total']
        rows << (
          Array('*') + Array('*') + Array('*total*') +
          Array('%.5f' % total) +
          Array('%.2f' % (total * @yen)) +
          Array('%8.3f' % 100)
        )
      end

      if format == 'json'
        out = []
        rows.each do |r|
          record = {}
          head.each_with_index do |h, i|
            record[h.to_s] = r[i].strip
          end
          out << record
        end
        return out.to_json
      elsif format == 'csv'
        out = head.join(',') + "\n"
        rows.each do |r|
          out += r.join(',') + "\n"
        end
        return out
      else
        table = Text::Table.new
        table.head = head
        table.rows = rows
        table.align_column 4, :right
        table.align_column 5, :right
        table.align_column 6, :right
        return table.to_s
      end
    end

    private

    def acceptable_line?(line)
      if line['RecordType'] == 'PayerLineItem' && !line['ProductName'].nil?
        return true
      end
      if line['RecordType'] == 'LinkedLineItem' && !line['ProductName'].nil?
        return true
      end
      return false if line['TotalCost'].nil?
      false
    end

    def payment_key(project, linked)
      %(#{linked.delete("\n")}:#{project.to_s.delete("\n")})
    end

    def payment_description_key(payment_key, desc)
      %(#{payment_key}:#{desc.to_s.delete("\n")})
    end
  end
end

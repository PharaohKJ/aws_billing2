# coding: utf-8

module AwsBilling2
  class AwsBilling2
    def initialize(values)
      @aws_config = {}
      [:access_key_id, :secret_access_key, :region].each do |k|
        @aws_config[k] = values[k.to_s]
      end
      @yen = values[:ypd.to_s].to_f
      @pay = {}
      @payment = {}
      @payment_description = {}
      @format = values[:csv.to_s] ? 'csv' : 'cli'
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

    def parse(bucket_value)
      csv = CSV.new(bucket_value[1..-1].join("\n"), headers: true)
      csv.each do |l|
        next unless acceptable_line?(l)
        project = l['user:Project'].to_s == ''    ? 'none' : l['user:Project']
        linked  = l['LinkedAccountId'].to_s == '' ? 'none' : l['LinkedAccountId']
        @pay[payment_key(project, linked)] = [] if @pay[payment_key(project, linked)].nil?
        @pay[payment_key(project, linked)] << l
      end

      @pay.each do |k, l|
        l.sort! do |a, b|
          a['ProductName'].to_s <=> b['ProductName'].to_s
        end
        l.each do |p|
          next if p['TotalCost'].to_f < 0.00001 && @skip_zero_record == true
          # puts "Poject:#{k} #{p['ProductName']} : #{p['ItemDescription']} \n #{p['TotalCost']}"
          @payment[k] = 0 if @payment[k].nil?
          @payment['total'] = 0 if @payment['total'].nil?
          key = payment_description_key(k, p['ProductName'])
          @payment_description[key] = 0 if @payment_description[key].nil?
          cost = p['TotalCost'].to_f
          @payment[k] += cost
          @payment['total'] += cost
          @payment_description[key] += cost
        end
        # puts '---------'
      end
    end

    def gets_table(format = @format, with_total_record = @total_record)
      head = ['PayID', 'Tag', 'Item', '$', "Yen(#{@yen.to_i}/$)", '%']
      rows = []
      @payment_description.each do |k, l|
        rows << (
          Array(k.split('-')) +
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
          Array('%8.3f' % (100))
        )
      end

      if format == 'csv'
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
      return true  if line['RecordType'] == 'PayerLineItem'
      return true  if line['RecordType'] == 'LinkedLineItem'
      return false if line['TotalCost'].nil?
      false
    end

    def payment_key(project, linked)
      %(#{linked.delete("\n")}-#{project.delete("\n")})
    end

    def payment_description_key(payment_key, desc)
      %(#{payment_key}-#{desc.delete("\n")})
    end
  end
end

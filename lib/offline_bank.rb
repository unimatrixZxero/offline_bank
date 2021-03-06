require 'rubygems'
require 'open-uri'
require 'nokogiri'
require 'money'

class InvalidCache < StandardError ; end

class OfflineBank < Money::Bank::VariableExchange

  attr_accessor :last_updated
  attr_accessor :rates_updated_at

  CACHED_RATES = File.join ['.', 'lib', 'offline_rates']
  CURRENCIES = %w(USD JPY BGN CZK DKK GBP HUF ILS LTL PLN RON SEK CHF NOK HRK RUB TRY AUD BRL CAD CNY HKD IDR INR KRW MXN MYR NZD PHP SGD THB ZAR)

  def update_rates(cache=CACHED_RATES)
    update_parsed_rates(doc(cache))
  end

  def save_rates(cache)
    raise InvalidCache if !cache
    File.open(cache, "w") do |file|
      io = open(ECB_RATES_URL) ;
      io.each_line {|line| file.puts line}
    end
  end

  def update_rates_from_s(content)
    update_parsed_rates(doc_from_s(content))
  end

  def save_rates_to_s
    open(CACHED_RATES).read
  end

  def exchange(cents, from_currency, to_currency)
    exchange_with(Money.new(cents, from_currency), to_currency)
  end

  def exchange_with(from, to_currency)
    rate = get_rate(from.currency, to_currency)
    unless rate
      from_base_rate, to_base_rate = nil, nil
      @mutex.synchronize {
        from_base_rate = get_rate("EUR", from.currency, :without_mutex => true)
        to_base_rate = get_rate("EUR", to_currency, :without_mutex => true)
      }
      rate = to_base_rate / from_base_rate
    end
    Money.new(((BigDecimal(Money::Currency.wrap(to_currency).subunit_to_unit) / BigDecimal(from.currency.subunit_to_unit)) * from.cents * rate).round, to_currency)
  end

  protected

  def doc(cache)
    rates_source = !!cache ? cache : CACHED_RATES
    Nokogiri::XML(open(rates_source)).tap {|doc| doc.xpath('gesmes:Envelope/xmlns:Cube/xmlns:Cube//xmlns:Cube') }
  rescue Nokogiri::XML::XPath::SyntaxError
    Nokogiri::XML(open(CACHED_RATES))
  end

  def doc_from_s(content)
    Nokogiri::XML(content)
  end

  def update_parsed_rates(doc)
    rates = doc.xpath('gesmes:Envelope/xmlns:Cube/xmlns:Cube//xmlns:Cube')

    @mutex.synchronize do
      rates.each do |exchange_rate|
        rate = BigDecimal(exchange_rate.attribute("rate").value)
        currency = exchange_rate.attribute("currency").value
        set_rate("EUR", currency, rate, :without_mutex => true)
      end
      set_rate("EUR", "EUR", 1, :without_mutex => true)
    end

    rates_updated_at = doc.xpath('gesmes:Envelope/xmlns:Cube/xmlns:Cube/@time').first.value
    @rates_updated_at = Time.parse(rates_updated_at)

    @last_updated = Time.now
  end
end

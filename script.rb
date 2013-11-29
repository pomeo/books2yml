#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'net/http'

# логин с паролем для работы с api
@login = ''
@pass  = ''

# отсюда нам нужно название компании, урл и категории
xml = Nokogiri.XML(open('http://svoi-knigi.ru/marketplace/11698.xml'))

@yml_temp = xml.xpath('/yml_catalog/shop').map do |i|
  {
    'name' => i.at_xpath('name').content,
    'compname' => i.at_xpath('company').content,
    'url' => i.at_xpath('url').content
  }
end

# здесь мы получаем список категорий из прошлого xml, которые используются в финальном xml
@cats = xml.xpath('/yml_catalog/shop/categories/category').map do |c|
  {
    'id' => c.at_xpath('@id'),
    'pid' => c.at_xpath('@parentId'),
    'text' => c.content
  }
end

# p - переменная для страниц в урле, e - тригер, xml - финальный массив из которого строится конечный файл
@p = 1
@e = 0
@xml = []

while @e == 0  do
  # парсим xml
  doc = Nokogiri.XML(open('http://svoi-knigi.ru/admin/products.xml?per_page=250&page=%s' % @p, :http_basic_authentication=>[@login, @pass]))

  if doc.at_xpath('nil-classes')
    @e = 1
  else
    hash = doc.xpath('/products/product').map do |i|
      {
        'id' => i.at_xpath('id').content,
        'price' => i.at_xpath('variants/variant/price'),
        'currencyId' => 'RUR',
        'categoryId' => i.at_xpath('canonical-url-collection-id').content,
        'picture' => i.at_xpath('images/image/original-url'),
        'store' => 'true',
        'pickup' => 'true',
        'delivery' => 'true',
        'author' => i.at_xpath('characteristics/characteristic[property-id=395166]/title'),
        'name' => i.at_xpath('title').content,
        'publisher' => i.at_xpath('characteristics/characteristic[property-id=395165]/title'),
        'series' => i.at_xpath('characteristics/characteristic[property-id=395170]/title'),
        'year' => i.at_xpath('characteristics/characteristic[property-id=395194]/title'),
        'ISBN' => i.at_xpath('variants/variant/sku[not(@nil)]'),
        #'volume' => i.at_xpath('characteristics/characteristic[property-id=]/title'),
        #'part' => i.at_xpath('characteristics/characteristic[property-id=]/title'),
        'language' => i.at_xpath('characteristics/characteristic[property-id=395642]/title'),
        'binding' => i.at_xpath('characteristics/characteristic[property-id=395168]/title'),
        'page_extent' => i.at_xpath('characteristics/characteristic[property-id=395169]/title'),
        'description' => i.at_xpath('description[not(@nil)]'),
        'downloadable' => 'false',
        'quantity' => i.at_xpath('//variants/variant/quantity').content
      }
    end
  end
  
  @xml.concat(hash)
  @p +=1
end

# создаём YML
 builder = Nokogiri::XML::Builder.new(:encoding => 'windows-1251') do |yml|
   yml.doc.create_internal_subset('yml_catalog', nil, 'http://partner.market.yandex.ru/pages/help/shops.dtd')
   yml.yml_catalog(:date => DateTime.now.new_offset(4.0/24).strftime('%Y-%m-%d %H:%M')) {
   yml.shop {
     yml.name @yml_temp[0]['name']
     yml.company @yml_temp[0]['compname']
     yml.url @yml_temp[0]['url']
     yml.currencies {
       yml.currency(:id => 'RUR', :rate => '1')
     }
     yml.categories {
       @cats.each do |c|
          yml.category(:id => c['id'], :parentId => c['pid']) {
            yml.text(c['text'])
          }
       end
     }
     yml.offers {
       @xml.each do |o|
         yml.offer(:id => o['id'], :type => 'book', :available => o['quantity'] == '0' ? 'false' : 'true') {
            yml.url @yml_temp[0]['url'] + '/product_by_id/' + o['id']
            yml.price o['price'].content
            yml.currencyId o['currencyId']
            yml.categoryId(:type => 'Own') {
              yml.text(o['categoryId'])
            }
            if (o['picture'] != nil)
              yml.picture o['picture'].content
            end
            yml.store o['store']
            yml.pickup o['pickup']
            yml.delivery o['delivery']
            if (o['author'] != nil)
              yml.author o['author'].content
            end
            yml.name o['name']
            if (o['publisher'] != nil)
              yml.publisher o['publisher'].content
            end
            if (o['series'] != nil)
              yml.series o['series'].content
            end
            if (o['year'] != nil)
              yml.year o['year'].content
            end
            if (o['ISBN'] != nil)
              yml.ISBN o['ISBN'].content
            end
            if (o['language'] != nil)
              yml.language o['language'].content
            end
            if (o['binding'] != nil)
              yml.binding o['binding'].content
            end
            if (o['page_extent'] != nil)
              yml.page_extent o['page_extent'].content
            end
            if (o['description'] != nil)
              yml.description o['description'].content
            end
            yml.downloadable o['downloadable']
         }
       end
     }
   }
 }
 end

 #пишем конечный результат в файл
 File.open(File.expand_path(File.join(File.dirname(__FILE__))) + '/output.xml', 'w') {
   |file| file.write(builder.to_xml)
 }

# адрес api куда мы будем отправлять получившийся файл
uri = URI('http://svoi-knigi.ru/admin/files.xml')

# ищем старый output.xml
fl = Nokogiri.XML(open('http://svoi-knigi.ru/admin/files.xml', :http_basic_authentication=>[@login, @pass]))
@chkf = fl.xpath('/files').map do |f|
  {
    'id' => f.xpath('//file[contains(.,"output")]/id')
  }
end

# и если он есть, удаляем
if (@chkf[0]['id'].text() != '')
  url = URI('http://svoi-knigi.ru/admin/files/%s.xml' % @chkf[0]['id'].text())
  req = Net::HTTP::Delete.new(URI(url))
  req.basic_auth @login, @pass
  req.content_type = 'application/xml'
  res = Net::HTTP.start(url.hostname, url.port) {|http|
    http.request(req)
  }
end

# делаем запрос к api, для отправки нового файла
req = Net::HTTP::Post.new(uri)
req.basic_auth @login, @pass

# в теле сообщения не получилось передать разными способами сам файл, поэтому запрашиваем его с другого домена
xmlpost = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
  xml.file {
    xml.src ''
  }
end

req.body = xmlpost.to_xml
req.content_type = 'application/xml'

res = Net::HTTP.start(uri.hostname, uri.port) {|http|
  http.request(req)
}

# выводим результат запроса на всякий случай
puts res.body

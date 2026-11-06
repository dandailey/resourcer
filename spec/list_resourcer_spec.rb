# frozen_string_literal: true

require "spec_helper"

class Account < ActiveRecord::Base
  has_many :companies
end

class Company < ActiveRecord::Base
  belongs_to :account
  has_many :orders
  has_many :gadgets
end

class Order < ActiveRecord::Base
  belongs_to :company
end

class Gadget < ActiveRecord::Base
end

class Event < ActiveRecord::Base
end

class Voucher < ActiveRecord::Base
  self.table_name = "orders"
end

# These two refer to each other, so neither class exists when the first is defined.
class CompanyResourcer < Resourcer::ListResourcer
  index_by :kind
  relates_to :account, :orders, :gadgets

  def company_names
    list.map(&:name)
  end

  module ObjectResourcerMethods
    def order_total
      orders.sum(&:total)
    end
  end
end

class OrderResourcer < Resourcer::ListResourcer
  index_by :company_id
  relates_to :company
end

class AccountResourcer < Resourcer::ListResourcer
end

class GadgetResourcer < Resourcer::ListResourcer
end

class EventResourcer < Resourcer::ListResourcer
end

RSpec.describe Resourcer::ListResourcer do
  let(:account_a) { Account.create!(name: "a") }
  let(:account_b) { Account.create!(name: "b") }
  let!(:company_1) { Company.create!(name: "one", kind: "llc", account_id: account_a.id) }
  let!(:company_2) { Company.create!(name: "two", kind: "llc", account_id: account_a.id) }
  let!(:company_3) { Company.create!(name: "three", kind: "corp", account_id: account_b.id) }
  let!(:order_1) { Order.create!(company_id: company_1.id, total: 10) }
  let!(:order_2) { Order.create!(company_id: company_1.id, total: 20) }
  let!(:order_3) { Order.create!(company_id: company_2.id, total: 5) }
  let(:resourcer) { CompanyResourcer.new(Company.order(:id)) }

  after { [Gadget, Order, Company, Account, Event].each(&:delete_all) }

  describe "assimilating records" do
    it "accepts a relation, an array or a single record" do
      expect(CompanyResourcer.new(Company.all).id_list).to contain_exactly(company_1.id, company_2.id, company_3.id)
      expect(CompanyResourcer.new([company_1, company_2]).id_list).to eq([company_1.id, company_2.id])
      expect(CompanyResourcer.new(company_1).id_list).to eq([company_1.id])
    end

    it "indexes records by primary key" do
      expect(resourcer.lookup(company_2.id)).to eq(company_2)
      expect(resourcer.lookup([company_1.id, company_3.id])).to eq([company_1, company_3])
      expect(resourcer.object_lookup.keys).to eq(resourcer.id_list)
    end

    it "marks every record as resourced" do
      expect(resourcer.list).to all(be_is_resourced)
    end

    it "names its accessors after the model" do
      expect(resourcer.company_list).to eq(resourcer.list)
      expect(resourcer.company_id_list).to eq(resourcer.id_list)
      expect(resourcer.company_lookup).to eq(resourcer.object_lookup)
    end

    it "builds from a list and returns the resourced records" do
      list = CompanyResourcer.build(Company.order(:id))

      expect(list).to eq([company_1, company_2, company_3])
      expect(list).to all(be_is_resourced)
    end

    it "handles a model with no primary key" do
      Event.insert_all!([{label: "x"}, {label: "y"}])

      expect(EventResourcer.new(Event.all).list.map(&:label)).to contain_exactly("x", "y")
    end

    it "tells a host app's Fetchable about each record when there is one" do
      registered = []
      stub_const("Fetchable", Class.new { define_singleton_method(:register_object) { |obj| registered << obj } })

      CompanyResourcer.new([company_1])

      expect(registered).to eq([company_1])
    end
  end

  describe "index_by" do
    it "lists unique values" do
      expect(resourcer.unique_kind_list).to contain_exactly("llc", "corp")
    end

    it "groups records" do
      expect(resourcer.grouped_by_kind["llc"]).to eq([company_1, company_2])
    end

    it "finds records for one value or several" do
      expect(resourcer.list_for_kind("corp")).to eq([company_3])
      expect(resourcer.list_for_kind(["corp", "llc"])).to contain_exactly(company_1, company_2, company_3)
      expect(resourcer.list_for_kind("none")).to eq([])
    end

    it "builds an index on demand for a field that was not declared" do
      expect(resourcer.unique_values_for(:name)).to contain_exactly("one", "two", "three")
      expect(resourcer.grouped_object_lookup_for(:name)["two"]).to eq([company_2])
    end
  end

  describe "relates_to a belongs_to association" do
    it "loads all the related records once" do
      list = resourcer.list

      queries = count_queries do
        expect(list[0].resourcer.account).to eq(account_a)
        expect(list[1].resourcer.account).to eq(account_a)
        expect(list[2].resourcer.account).to eq(account_b)
      end

      expect(queries).to eq(1)
    end

    it "exposes the related resourcer and lists" do
      expect(resourcer.account_resourcer).to be_a(AccountResourcer)
      expect(resourcer.account_id_list).to contain_exactly(account_a.id, account_b.id)
      expect(resourcer.account_lookup[account_b.id]).to eq(account_b)
    end

    it "indexes the foreign key" do
      expect(resourcer.unique_account_id_list).to contain_exactly(account_a.id, account_b.id)
    end
  end

  describe "relates_to a has_many association" do
    it "loads all the related records once" do
      list = resourcer.list

      queries = count_queries do
        expect(list[0].resourcer.orders).to contain_exactly(order_1, order_2)
        expect(list[1].resourcer.orders).to eq([order_3])
        expect(list[2].resourcer.orders).to eq([])
      end

      expect(queries).to eq(1)
    end

    it "works when the related resourcer does not index the foreign key" do
      gadget = Gadget.create!(company_id: company_2.id)

      expect(resourcer.list[1].resourcer.gadgets).to eq([gadget])
      expect(resourcer.list[0].resourcer.gadgets).to eq([])
    end

    it "does not query until the data is needed" do
      expect(count_queries { resourcer }).to eq(1)
    end

    it "resources the related records too" do
      order = resourcer.list[0].resourcer.orders.first

      expect(order).to be_is_resourced
      expect(order.resourcer.list_for_company_id(company_1.id)).to contain_exactly(order_1, order_2)
    end

    it "walks across several levels without further queries" do
      list = resourcer.list
      list[0].resourcer.orders.first.resourcer.company

      queries = count_queries { list[1].resourcer.orders.first.resourcer.company }

      expect(queries).to eq(0)
    end
  end

  describe "custom methods and pass-through" do
    let(:company) { resourcer.list.first }

    it "adds ObjectResourcerMethods to each record's resourcer" do
      expect(company.resourcer.order_total).to eq(30)
    end

    it "passes unknown methods to the list resourcer, then the record" do
      expect(company.resourcer.company_names).to eq(["one", "two", "three"])
      expect(company.resourcer.name).to eq("one")
    end

    it "lets the record reach its resourcer's methods" do
      expect(company.order_total).to eq(30)
    end

    it "exposes the record under its model's name" do
      expect(company.resourcer.company).to eq(company)
    end

    it "raises for a method nothing responds to" do
      expect { company.resourcer.not_a_method }.to raise_error(NoMethodError)
    end
  end

  describe "records without a list resourcer" do
    it "gets a default pass-through resourcer" do
      company = Company.find(company_1.id)

      expect(company).not_to be_is_resourced
      expect(company.resourcer.name).to eq("one")
      expect(company.resourcer.account).to eq(account_a)
    end

    it "works for a model with no resourcer class" do
      voucher = Voucher.first

      expect(voucher.resourcer.total).to eq(voucher.total)
    end

    it "can be resourced later" do
      company = Company.find(company_1.id)

      company.apply_resourcer(resourcer)

      expect(company).to be_is_resourced
      expect(company.resourcer.orders).to contain_exactly(order_1, order_2)
    end

    it "builds its own resourcer with auto_resourcer" do
      expect(Company.find(company_1.id).auto_resourcer.orders).to contain_exactly(order_1, order_2)
    end
  end
end

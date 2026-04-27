# frozen_string_literal: true

require "test_helper"

module RailsLti
  class NonceTest < ActiveSupport::TestCase
    test "is valid with value and future expiry" do
      nonce = Nonce.new(value: "abc123", expires_at: 10.minutes.from_now)
      assert nonce.valid?
    end

    test "requires value" do
      nonce = Nonce.new(expires_at: 10.minutes.from_now)
      refute nonce.valid?
    end

    test "requires expires_at" do
      nonce = Nonce.new(value: "abc123")
      refute nonce.valid?
    end

    test "expired? returns false for future nonce" do
      nonce = Nonce.new(value: "abc123", expires_at: 10.minutes.from_now)
      refute nonce.expired?
    end

    test "expired? returns true for past nonce" do
      nonce = Nonce.new(value: "abc123", expires_at: 10.minutes.ago)
      assert nonce.expired?
    end

    test "cleanup_expired! removes expired nonces" do
      Nonce.create!(value: "expired_1", expires_at: 1.minute.ago)
      Nonce.create!(value: "expired_2", expires_at: 2.minutes.ago)
      Nonce.create!(value: "valid_1",   expires_at: 10.minutes.from_now)

      assert_difference "Nonce.count", -2 do
        Nonce.cleanup_expired!
      end

      assert Nonce.exists?(value: "valid_1")
    end

    test "enforces unique nonce value" do
      Nonce.create!(value: "unique_nonce", expires_at: 10.minutes.from_now)
      dup = Nonce.new(value: "unique_nonce", expires_at: 10.minutes.from_now)
      refute dup.valid?
    end
  end
end

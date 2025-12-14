require "openssl"

lib LibCrypto
  struct ASN1_TIME
    length : Int32
    type : Int32
    data : Char*
    flags : Long
  end

  fun x509_get0_notAfter = X509_get0_notAfter(x : X509*) : ASN1_TIME*
  fun x509_get0_notBefore = X509_get0_notBefore(x : X509*) : ASN1_TIME*
end

module OpenSSL::X509
  class Certificate
    def not_after
      ptr = @cert.as(LibCrypto::X509*)
      not_after = LibCrypto.x509_get0_notAfter(ptr)
      raise Error.new("Failed to fetch not_after") if not_after.null?
      asn1_time_to_time(not_after.value)
    end

    private def asn1_time_to_time(asn1_time)
      data = String.new(asn1_time.data)
      case data
        # GeneralizedTime
      when /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:\.(\d{3}))\S+$/
        Time.utc(
          year: $1.to_i,
          month: $2.to_i,
          day: $3.to_i,
          hour: $4.to_i,
          minute: $5.to_i,
          second: $6.to_i
        )
      when /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\S+$/
        Time.utc(
          year: $1.to_i + 2000,
          month: $2.to_i,
          day: $3.to_i,
          hour: $4.to_i,
          minute: $5.to_i,
          second: $6.to_i
        )
      else
        raise "Unsupported time format for #{data} (type=#{asn1_time.type})"
      end
    end
  end
end

module ActiveSupport
  if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'
    WeakHash = ::Weakling::WeakHash
  else
    class WeakHash
      def initialize(cache = Hash.new)
        @cache = cache
        @key_map = {}
        @rev_cache = Hash.new{|h,k| h[k] = {}}
        @reclaim_value = lambda do |value_id|
          if value = @rev_cache.delete(value_id)
            value.each_key{|key| @cache.delete key}
          end
        end
      end

      def [](key)
        value_id = @cache[key]
        value_id && ObjectSpace._id2ref(value_id)
      rescue RangeError
        nil
      end

      def []=(key, value)
        key2 = case key
               when Fixnum, Symbol, true, false, nil
                 key
               else
                 key.dup
               end

        @rev_cache[value.object_id][key2] = true
        @cache[key2] = value.object_id
        @key_map[key.object_id] = key2

        ObjectSpace.define_finalizer(value, @reclaim_value)
      end

      def clear
        @cache.clear
      end

      def delete(key)
        @cache.delete(key)
      end
    end
  end
end
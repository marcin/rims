# -*- coding: utf-8 -*-

require 'digest'
require 'set'

module RIMS
  class DB
    def initialize(kv_store)
      @db = kv_store
    end

    def sync
      @db.sync
      self
    end

    def close
      @db.close
      self
    end

  end

  class GlobalDB < DB
    def setup
      [ %w[ cnum 0 ],
        %w[ uid 1 ],
        %w[ uidvalidity 1 ]
      ].each do |k, v|
        @db[k] = v unless (@db.key? k)
      end

      self
    end

    def cnum
      @db['cnum'].to_i
    end

    def cnum=(n)
      @db['cnum'] = n.to_s
      n
    end

    def uid
      @db['uid'].to_i
    end

    def uid=(id)
      @db['uid'] = id.to_s
      id
    end

    def uidvalidity
      @db['uidvalidity'].to_i
    end

    def uidvalidity=(id)
      @db['uidvalidity'] = id.to_s
      id
    end

    def add_mbox(id, name)
      if (@db.key? "mbox_id-#{id}") then
        raise "internal error: duplicated mailbox id <#{id}>."
      end
      @db["mbox_id-#{id}"] = name
      @db["mbox_name-#{name}"] = id.to_s
      self
    end

    def del_mbox(id)
      name = @db.delete("mbox_id-#{id}")
      unless (name) then
        return
      end

      id2 = @db.delete("mbox_name-#{name}")
      unless (id2) then
        raise "internal error: not found a mailbox name entry at `{id}'"
      end
      if (id2.to_i != id) then
        raise "internal error: expected id <#{id}> but was <#{id2}>."
      end

      name
    end

    def mbox_name(id)
      @db["mbox_id-#{id}"]
    end

    def mbox_id(name)
      v = @db["mbox_name-#{name}"] and v.to_i
    end

    def each_mbox_id
      return enum_for(:each_mbox_id) unless block_given?
      @db.each_key do |key|
        if (key =~ /^mbox_id-\d+$/) then
          yield($&[8..-1].to_i)
        end
      end
      self
    end
  end

  class MessageDB
    def initialize(text_st, attr_st)
      @text_st = text_st
      @attr_st = attr_st
    end

    def sync
      @text_st.sync
      @attr_st.sync
      self
    end

    def close
      errors = []
      for db in [ @text_st, @attr_st ]
        begin
          db.close
        rescue
          errors << $!
        end
      end

      unless (errors.empty?) then
        if (errors.length == 1) then
          raise errors[0]
        else
          raise 'failed to close message db: ' + errors.map{|ex| "[#{ex.class}] #{ex.message}" }.join(', ')
        end
      end

      self
    end

    def add_msg(id, text, date=Time.now)
      if (@text_st.key? id.to_s) then
        raise "internal error: duplicated message id <#{id}>."
      end

      @text_st[id.to_s] = text
      @attr_st["date-#{id}"] = Marshal.dump(date)
      @attr_st["cksum-#{id}"] = 'sha256:' + Digest::SHA256.hexdigest(text)

      self
    end

    def msg_text(id)
      @text_st[id.to_s]
    end

    def msg_date(id)
      if (date_bin = @attr_st["date-#{id}"]) then
        Marshal.load(date_bin)
      end
    end

    def msg_cksum(id)
      @attr_st["cksum-#{id}"]
    end

    def each_msg_id
      return enum_for(:each_msg_id) unless block_given?
      @text_st.each_key do |key|
        yield(key.to_i)
      end
      self
    end

    def msg_flag(id, name)
      msg_cksum(id) or raise "not found a message at `#{id}'."
      case (v = @attr_st["flag_#{name}-#{id}"])
      when 'true'
        true
      when 'false'
        false
      else
        raise "internal error: unexpected #{name} flag value at #{id}: #{v}"
      end
    end

    def set_msg_flag(id, name, value)
      msg_cksum(id) or raise "not found a message at `#{id}'."
      old_flag_value = @attr_st["flag_#{name}-#{id}"]
      new_flag_value = value ? 'true' : 'false'
      @attr_st["flag_#{name}-#{id}"] = new_flag_value
      self if (old_flag_value != new_flag_value)
    end

    def msg_mboxes(id)
      msg_cksum(id) or raise "not found a message at `#{id}'."
      if (@attr_st.key? "mbox-#{id}") then
        @attr_st["mbox-#{id}"].split(/,/).map{|s| s.to_i }.to_set
      else
        [].to_set
      end
    end

    def add_msg_mbox(id, mbox_id)
      msg_cksum(id) or raise "not found a message at `#{id}'."
      id_set = msg_mboxes(id)
      id_set << mbox_id
      @attr_st["mbox-#{id}"] = id_set.to_a.join(',')
      self
    end

    def del_msg_mbox(id, mbox_id)
      msg_cksum(id) or raise "not found a message at `#{id}'."
      id_set = msg_mboxes(id)
      return unless (id_set.include? mbox_id)
      id_set.delete(mbox_id)
      @attr_st["mbox-#{id}"] = id_set.to_a.join(',')
      self
    end
  end

  class MailboxDB < DB
    def mbox_id
      if (id = @db['mbox_id']) then
        id.to_i
      end
    end

    def mbox_id=(id)
      @db['mbox_id'] = id.to_s
      id
    end

    def mbox_name
      @db['mbox_name']
    end

    def mbox_name=(name)
      @db['mbox_name'] = name
      name
    end

    def setup
      [ %w[ msg_count 0 ],
        %w[ flags_answered 0 ],
        %w[ flags_flagged 0 ],
        %w[ flags_deleted 0 ],
        %w[ flags_seen 0 ],
        %w[ flags_draft 0 ],
        %w[ flags_recent 0 ]
      ].each do |k, v|
        @db[k] = v unless (@db.key? k)
      end

      self
    end

    def msgs
      count = @db['msg_count'] or raise 'not initialized msg_count.'
      count.to_i
    end

    def msgs_increment
      next_count = msgs + 1
      @db['msg_count'] = next_count.to_s
      next_count
    end

    def msgs_decrement
      next_count = msgs - 1
      if (next_count < 0) then
        raise 'negative message count.'
      end
      @db['msg_count'] = next_count.to_s
      next_count
    end

    def flags(name)
      count = @db["flags_#{name}"] or raise "not initialized flags_#{name}"
      count.to_i
    end

    def flags_increment(name)
      next_count = flags(name) + 1
      @db["flags_#{name}"] = next_count.to_s
      next_count
    end

    def flags_decrement(name)
      next_count = flags(name) - 1
      if (next_count < 0) then
        raise "negative flag count: #{name}."
      end
      @db["flags_#{name}"] = next_count.to_s
      next_count
    end

    def add_msg(id)
      unless (exist_msg? id) then
        @db["msg-#{id}"] = ''
        msgs_increment
        self
      end
    end

    def exist_msg?(id)
      @db.key? "msg-#{id}"
    end

    def msg_flag_del(id)
      (exist_msg? id) or raise "not exist message: #{id}."
      @db["msg-#{id}"] == 'deleted'
    end

    def set_msg_flag_del(id, value)
      (exist_msg? id) or raise "not exist message: #{id}."
      old_flag_value = @db["msg-#{id}"]
      new_flag_value = value ? 'deleted' : ''
      @db["msg-#{id}"] = new_flag_value
      self if (old_flag_value != new_flag_value)
    end

    def expunge_msg(id)
      (exist_msg? id) or raise "not exist message: #{id}."
      msg_flag_del(id) or raise "no deleted flag: #{id}."
      @db.delete("msg-#{id}")
      msgs_decrement
      self
    end

    def each_msg_id
      return enum_for(:each_msg_id) unless block_given?
      @db.each_key do |key|
        if (key =~ /^msg-\d+$/) then
          yield($&[4..-1].to_i)
        end
      end
      self
    end
  end
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:

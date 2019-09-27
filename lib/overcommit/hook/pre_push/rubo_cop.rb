# frozen_string_literal: true

require 'overcommit/hook/shared/rubo_cop'

module Overcommit::Hook::PrePush
  # (see Overcommit::Hook::Shared::RuboCop)
  class RuboCop < Base
    include Overcommit::Hook::Shared::RuboCop
  end
end

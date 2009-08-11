#--
# Copyright (c) 2005-2009, John Mettraux, jmettraux@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Made in Japan.
#++


require 'ruote/exp/flowexpression'
require 'ruote/exp/merge'


module Ruote

  #
  # The 'concurrence' expression applies its child branches in parallel
  # (well it makes a best effort to make them run in parallel).
  #
  #    concurrence do
  #      alpha
  #      bravo
  #    end
  #
  class ConcurrenceExpression < FlowExpression

    include MergeMixin

    names :concurrence

    def apply

      @count = attribute(:count).to_i rescue nil
      @count = nil if @count && @count < 1

      @merge = att(:merge, %w[ first last highest lowest ])
      @merge_type = att(:merge_type, %w[ override mix isolate ])
      @remaining = att(:remaining, %w[ cancel forget ])

      @workitems = nil

      @over = false

      apply_children
    end

    def reply (workitem)

      return if @over

      if @merge == 'first' || @merge == 'last'
        (@workitems ||= []) << workitem
      else
        (@workitems ||= {})[workitem.fei.expid] = workitem
      end

      @over = over?(workitem)

      if newer_exp_version = persist(true)
        #
        # oops, collision detected (with other instance of the same engine)
        #
        return newer_exp_version.reply(workitem)
      end

      reply_to_parent(nil) if @over
    end

    protected

    def apply_children

      tree_children.each_with_index do |c, i|
        apply_child(i, @applied_workitem.dup)
      end
    end

    def over? (workitem)

      over_if = attribute(:over_if, workitem)

      if over_if && Condition.true?(over_if)
        true
      else
        @workitems && (@workitems.size >= expected_count)
      end
    end

    # How many branch replies are expected before the concurrence is over ?
    #
    def expected_count

      @count ? [ @count, tree_children.size ].min : tree_children.size
    end

    def reply_to_parent (_workitem)

      handle_remaining if @children

      super(merge_all_workitems)
    end

    def merge_all_workitems

      return @applied_workitem unless @workitems

      wis = case @merge
      when 'first'
        @workitems.reverse
      when 'last'
        @workitems
      when 'highest', 'lowest'
        is = @workitems.keys.sort.collect { |k| @workitems[k] }
        @merge == 'highest' ? is.reverse : is
      end

      wis.inject(nil) { |t, wi| merge_workitems(t, wi, @merge_type) }
    end

    def handle_remaining

      b = @remaining == 'cancel' ?
        lambda { |fei| pool.cancel_expression(fei, nil) } :
        lambda { |fei| pool.forget_expression(fei) }

      @children.each(&b)
    end
  end
end


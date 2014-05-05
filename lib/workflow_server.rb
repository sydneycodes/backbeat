# -*- encoding : utf-8 -*-
require 'workflow_server/config'
require 'workflow_server/logger'
require 'workflow_server/helper'
require 'workflow_server/errors'
require 'workflow_server/async'
require 'workflow_server/models'
require 'workflow_server/client'
require 'workflow_server/middlewares'
require 'workflow_server/version'
require 'workflow_server/workers'

module WorkflowServer
  extend WorkflowServer::Logger

  class << self
    LOCK_TIMEOUT = 160

    def schedule_next_decision(workflow)
      workflow.with_lock(timeout: LOCK_TIMEOUT) do
        Timeout::timeout(LOCK_TIMEOUT - 10) do #we give it an extra 10 seconds so we for sure timeout before the DB lock 
          self.info(id: workflow.id, message: :schedule_next_decision_lock_start, source: self.to_s)

          find_and_start_next_decision(workflow)

          self.info(id: workflow.id, message: :schedule_next_decision_lock_complete, source: self.to_s)
        end
      end
    rescue Timeout::Error => e
      self.info(id: workflow.id, message: :schedule_next_decision_timed_out, source: self.to_s)
      raise Backbeat::TransientError.new(e) 
    end

    def find_and_start_next_decision(workflow)      
      if workflow.decisions.not_in(:status => [:complete, :open, :resolved]).empty?
        if (next_decision = workflow.decisions.where(status: :open).first)
          self.info(id: workflow.id, message: :schedule_next_decision_lock_decision, decision: next_decision.id, source: self.to_s)
          next_decision.start
        end
      end
    end

    def get_event(id)
      Models::Event.find(id)
    end

    # options include workflow_type: workflow_type, subject: subject, decider: decider, name: workflow_type, user: user
    WORKFLOW_ATTRIBUTES = [:subject, :workflow_type, :decider, :name, :user].freeze
    def find_or_create_workflow(options = {})
      attributes = {}
      WORKFLOW_ATTRIBUTES.each { |k| attributes[k] = options[k] }
      attributes[:name] ||= attributes[:workflow_type]

      retried = false
      begin
        # find_or_create_by is not an atomic operation in mongodb. Mongoid instead runs two separate
        # queries (first to find and second to create when not found). There is a good chance of race
        # condition here. We catch such exceptions and retry this block of code again.
        workflow = Models::Workflow.find_or_create_by(attributes)
        workflow.save
        workflow
      rescue Moped::Errors::OperationFailure => error
        if error.message =~ /duplicate key error/ && !retried
          retried = true
          retry
        end
        raise
      end
    end
  end
end

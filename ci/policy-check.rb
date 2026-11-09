#!/usr/bin/env ruby
# frozen_string_literal: true
#
# policy-check.rb — repo-specific rules that schema validation (kubeconform) can't express.
# Runs over rendered Helm output and raw manifests; each violation prints one line, and any
# violation exits 1.
#
# Usage: ruby ci/policy-check.rb <manifest.yaml>...
#
# Rules:
#   scrape-port      A Service or pod template annotated prometheus.io/scrape: "true" must also
#                    set prometheus.io/port. VictoriaMetrics' kubernetes-pods and
#                    kubernetes-service-endpoints jobs keep_if_equal on that annotation, so
#                    without it the target is silently dropped.
#   memory-limit     Every container in a Deployment/StatefulSet/DaemonSet must set
#                    resources.limits.memory — an unbounded pod can OOM the controller or a Zero.
#                    Workloads with replicas: 0 are skipped.
#   vm-scrape-reload A container started with -promscrape.config must also set
#                    -promscrape.configCheckInterval; the VictoriaMetrics chart doesn't restart
#                    the pod when the scrape ConfigMap changes, so edits would never load.
#
# Exceptions go in EXCEPTIONS below as "rule:Kind/name/container", each with a reason.

require 'yaml'

EXCEPTIONS = {
}.freeze

WORKLOADS = %w[Deployment StatefulSet DaemonSet].freeze
violations = []

def annotated_scrape?(annotations)
  (annotations || {})['prometheus.io/scrape'].to_s == 'true'
end

def check(violations, rule, id, message)
  key = "#{rule}:#{id}"
  violations << "#{rule.ljust(16)} #{id}: #{message}" unless EXCEPTIONS.key?(key)
end

abort('usage: policy-check.rb <manifest.yaml>...') if ARGV.empty?

ARGV.each do |file|
  YAML.load_stream(File.read(file)) do |doc|
    next unless doc.is_a?(Hash) && doc['kind']

    kind = doc['kind']
    name = doc.dig('metadata', 'name')

    if kind == 'Service' && annotated_scrape?(doc.dig('metadata', 'annotations')) &&
       !doc.dig('metadata', 'annotations').key?('prometheus.io/port')
      check(violations, 'scrape-port', "Service/#{name}", 'prometheus.io/scrape without prometheus.io/port')
    end

    next unless WORKLOADS.include?(kind)
    next if doc.dig('spec', 'replicas') == 0 # scaled to zero (e.g. ArgoCD applicationset): no pods

    pod = doc.dig('spec', 'template') || {}
    pod_annotations = pod.dig('metadata', 'annotations')
    if annotated_scrape?(pod_annotations) && !pod_annotations.key?('prometheus.io/port')
      check(violations, 'scrape-port', "#{kind}/#{name}", 'pod prometheus.io/scrape without prometheus.io/port')
    end

    (pod.dig('spec', 'containers') || []).each do |c|
      id = "#{kind}/#{name}/#{c['name']}"
      unless c.dig('resources', 'limits', 'memory')
        check(violations, 'memory-limit', id, 'no resources.limits.memory')
      end

      args = (c['args'] || []) + (c['command'] || [])
      if args.any? { |a| a.to_s.start_with?('--promscrape.config=', '-promscrape.config=') } &&
         args.none? { |a| a.to_s.match?(/\A--?promscrape\.configCheckInterval=/) }
        check(violations, 'vm-scrape-reload', id, '-promscrape.config without -promscrape.configCheckInterval')
      end
    end
  end
end

if violations.empty?
  puts "policy-check: OK (#{ARGV.size} file(s), #{EXCEPTIONS.size} documented exception(s))"
else
  puts violations
  abort "policy-check: #{violations.size} violation(s)"
end

#!/usr/bin/env ruby
# frozen_string_literal: true
#
# render-argocd-apps.rb — render every Helm chart deployed by an ArgoCD Application in
# cluster/argocd/addons/ (MetalLB, Traefik, VictoriaMetrics, vmalert, kube-state-metrics, …)
# exactly as ArgoCD would: same chart, version, release name, namespace, and Git value files.
# helmfile.yaml only covers ArgoCD itself, so without this those charts get no CI coverage.
#
# Usage: ruby ci/render-argocd-apps.rb <output.yaml>
# Env:   KUBE_VERSION (default 1.37.0) — passed to helm template --kube-version
#
# Ruby (stdlib YAML) rather than Python: it's on macOS and the GitHub runners with no installs.

require 'yaml'
require 'open3'
require 'tmpdir'
require 'fileutils'

out = ARGV[0] or abort('usage: render-argocd-apps.rb <output.yaml>')
root = File.expand_path('..', __dir__)
kube_version = ENV.fetch('KUBE_VERSION', '1.37.0')
rendered = []

# Isolated Helm repo config/cache: charts are fetched by URL, so a developer's own (possibly
# stale) `helm repo` entries can't break or influence the render. Same behaviour locally and in CI.
helm_home = Dir.mktmpdir('render-argocd-apps')
at_exit { FileUtils.remove_entry(helm_home) if File.directory?(helm_home) }
helm_env = {
  'HELM_REPOSITORY_CONFIG' => File.join(helm_home, 'repositories.yaml'),
  'HELM_REPOSITORY_CACHE' => File.join(helm_home, 'repository'),
  'HELM_CACHE_HOME' => File.join(helm_home, 'cache')
}

Dir.glob(File.join(root, 'cluster/argocd/addons/*.yaml')).sort.each do |file|
  YAML.load_stream(File.read(file)) do |app|
    next unless app.is_a?(Hash) && app['kind'] == 'Application'

    spec = app['spec']
    name = app['metadata']['name']
    namespace = spec.dig('destination', 'namespace') || 'default'
    sources = spec['sources'] || [spec['source']]

    sources.compact.each do |src|
      next unless src['chart'] # Git path sources are plain manifests, validated elsewhere

      helm = src['helm'] || {}
      unsupported = helm.keys - ['valueFiles']
      abort("#{File.basename(file)}: helm.#{unsupported.join(', ')} not supported — extend this script") unless unsupported.empty?

      repo = src['repoURL']
      chart_args =
        if repo.start_with?('http://', 'https://')
          [src['chart'], '--repo', repo]
        else
          ["oci://#{repo}/#{src['chart']}"] # scheme-less repoURL = OCI registry (enableOCI)
        end
      value_args = (helm['valueFiles'] || []).flat_map do |v|
        ['-f', File.join(root, v.sub(%r{\A\$values/}, ''))]
      end

      cmd = ['helm', 'template', name, *chart_args, '--version', src['targetRevision'].to_s,
             '--namespace', namespace, '--kube-version', kube_version, *value_args]
      stdout, stderr, status = Open3.capture3(helm_env, *cmd)
      abort("#{name}: helm template failed\n#{stderr}") unless status.success?

      warn "==> rendered #{name} (#{src['chart']} #{src['targetRevision']})"
      rendered << "# ArgoCD Application: #{name}\n#{stdout}"
    end
  end
end

abort('no Helm-based ArgoCD Applications found') if rendered.empty?
File.write(out, rendered.join("\n---\n"))

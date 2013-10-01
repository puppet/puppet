namespace "ci" do
  task :spec do
    ENV["LOG_SPEC_ORDER"] = "true"
    sh %{rspec -r yarjuf -f JUnit -o result.xml -fd spec}
  end

  desc <<-EOS
    Check to see if the job at the url given in DOWNSTREAM_JOB has begun a build including the given BUILD_SELECTOR parameter.  An example `rake ci:check_for_downstream DOWNSTREAM_JOB='http://jenkins-foss.delivery.puppetlabs.net/job/Puppet-Package-Acceptance-master' BUILD_SELECTOR=123`
  EOS
  task :check_for_downstream do
    downstream_url = ENV['DOWNSTREAM_JOB'] || raise('No ENV DOWNSTREAM_JOB set!')
    downstream_url += '/api/json?depth=1'
    expected_selector = ENV['BUILD_SELECTOR'] || raise('No ENV BUILD_SELECTOR set!')
    puts "Waiting for a downstream job calling for BUILD_SELECTOR #{expected_selector}"
    success = false
    require 'json'
    require 'timeout'
    require 'net/http'
    Timeout.timeout(15 * 60) do
      loop do
        uri = URI(downstream_url)
        status = Net::HTTP.get(uri)
        json = JSON.parse(status)
        actions = json['builds'].first['actions']
        parameters = actions.select { |h| h.key?('parameters') }.first["parameters"]
        build_selector = parameters.select { |h| h['name'] == 'BUILD_SELECTOR' }.first['value']
        puts " * downstream job's last build selector: #{build_selector}"
        break if build_selector >= expected_selector
        sleep 60
      end
    end
  end

  desc "Tar up the acceptance/ directory so that package test runs have tests to run against."
  task :acceptance_artifacts do
    sh "cd acceptance; rm -f acceptance-artifacts.tar.gz; tar -czv --exclude .bundle -f acceptance-artifacts.tar.gz *"
  end
end

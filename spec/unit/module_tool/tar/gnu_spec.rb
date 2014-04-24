require 'spec_helper'
require 'puppet/module_tool'

describe Puppet::ModuleTool::Tar::Gnu do
  let(:sourcefile) { '/space path/the/module.tar.gz' }
  let(:destdir)    { '/space path/the/dest/dir' }
  let(:sourcedir)  { '/space path/the/src/dir' }
  let(:destfile)   { '/space path/the/dest/file.tar.gz' }

  it "unpacks a tar file" do
    Dir.expects(:chdir).with(destdir).yields(mock)
    Puppet::Util::Execution.expects(:execute).with(["gzip", "-dc", sourcefile])
    Puppet::Util::Execution.expects(:execpipe).with(["tar", "xof", "-"], true, 'w+')
    Puppet::Util::Execution.expects(:execute).with(["find", destdir, "-type", "d", "-exec", "chmod", "755", "{}", "+"])
    Puppet::Util::Execution.expects(:execute).with(["find", destdir, "-type", "f", "-exec", "chmod", "a-wst", "{}", "+"])
    Puppet::Util::Execution.expects(:execute).with(["chown", "-R", "<owner:group>", destdir])
    subject.unpack(sourcefile, destdir, '<owner:group>')
  end

  it "packs a tar file" do
    Puppet::Util::Execution.expects(:execute).with(["tar", "cf", "-", sourcedir])
    Puppet::Util::Execution.expects(:execpipe).with(["gzip", "-c"], true, 'w+')
    subject.pack(sourcedir, destfile)
  end
end

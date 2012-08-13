#!/usr/bin/env rspec
require 'spec_helper'

# We use this as a reasonable way to obtain all the support infrastructure.
[:user, :group].each do |type_for_this_round|
  provider_class = Puppet::Type.type(type_for_this_round).provider(:directoryservice)

  describe provider_class do
    before do
      @resource = stub("resource")
      @provider = provider_class.new(@resource)
    end

    it "[#6009] handle nested arrays of members" do
      current = ["foo", "bar", "baz"]
      desired = ["foo", ["quux"], "qorp"]
      group   = 'example'

      @resource.stubs(:[]).with(:name).returns(group)
      @resource.stubs(:[]).with(:auth_membership).returns(true)
      @provider.instance_variable_set(:@property_value_cache_hash,
                                      { :members => current })

      %w{bar baz}.each do |del|
        @provider.expects(:execute).once.
          with([:dseditgroup, '-o', 'edit', '-n', '.', '-d', del, group])
      end

      %w{quux qorp}.each do |add|
        @provider.expects(:execute).once.
          with([:dseditgroup, '-o', 'edit', '-n', '.', '-a', add, group])
      end

      expect { @provider.set(:members, desired) }.to_not raise_error
    end
  end
end

describe 'DirectoryService.single_report' do
  it 'fail on OS X < 10.5' do
    Puppet::Provider::NameService::DirectoryService.stubs(:get_macosx_version_major).returns("10.4")

    expect {
      Puppet::Provider::NameService::DirectoryService.single_report('resource_name')
    }.to raise_error(RuntimeError, "Puppet does not support OS X versions < 10.5")
  end

  it 'use plist data on >= 10.5' do
    Puppet::Provider::NameService::DirectoryService.expects(:get_macosx_version_major).twice.returns("10.5")
    Puppet::Provider::NameService::DirectoryService.expects(:get_ds_path).returns('Users')
    Puppet::Provider::NameService::DirectoryService.expects(:list_all_present).returns(
      ['root', 'user1', 'user2', 'resource_name']
    )
    Puppet::Provider::NameService::DirectoryService.expects(:generate_attribute_hash)
    Puppet::Provider::NameService::DirectoryService.expects(:execute)
    Puppet::Provider::NameService::DirectoryService.expects(:parse_dscl_plist_data)

    Puppet::Provider::NameService::DirectoryService.single_report('resource_name')
  end
end

describe 'DirectoryService.get_exec_preamble' do
  it 'fail on OS X < 10.5' do
    Puppet::Provider::NameService::DirectoryService.expects(:get_macosx_version_major).returns("10.4")

    expect {
      Puppet::Provider::NameService::DirectoryService.get_exec_preamble('-list')
    }.to raise_error(RuntimeError, "Puppet does not support OS X versions < 10.5")
  end

  it 'use plist data on >= 10.5' do
    Puppet::Provider::NameService::DirectoryService.expects(:get_macosx_version_major).returns("10.5")
    Puppet::Provider::NameService::DirectoryService.expects(:get_ds_path).returns('Users')

    Puppet::Provider::NameService::DirectoryService.get_exec_preamble('-list').should include("-plist")
  end
end

describe 'DirectoryService password behavior' do
  # The below is a binary plist containing a ShadowHashData key which CONTAINS
  # another binary plist. The nested binary plist contains a 'SALTED-SHA512'
  # key that contains a base64 encoded salted-SHA512 password hash...
  let (:salted_sha512_binary_plist) { "bplist00\324\001\002\003\004\005\006\a\bXCRAM-MD5RNT]SALTED-SHA512[RECOVERABLEO\020 \231k2\3360\200GI\201\355J\216\202\215y\243\001\206J\300\363\032\031\022\006\2359\024\257\217<\361O\020\020F\353\at\377\277\226\276c\306\254\031\037J(\235O\020D\335\006{\3744g@\377z\204\322\r\332t\021\330\n\003\246K\223\356\034!P\261\305t\035\346\352p\206\003n\247MMA\310\301Z<\366\246\023\0161W3\340\357\000\317T\t\301\311+\204\246L7\276\370\320*\245O\021\002\000k\024\221\270x\353\001\237\346D}\377?\265]\356+\243\v[\350\316a\340h\376<\322\266\327\016\306n\272r\t\212A\253L\216\214\205\016\241 [\360/\335\002#\\A\372\241a\261\346\346\\\251\330\312\365\016\n\341\017\016\225&;\322\\\004*\ru\316\372\a \362?8\031\247\231\030\030\267\315\023\v\343{@\227\301s\372h\212\000a\244&\231\366\nt\277\2036,\027bZ+\223W\212g\333`\264\331N\306\307\362\257(^~ b\262\247&\231\261t\341\231%\244\247\203eOt\365\271\201\273\330\350\363C^A\327F\214!\217hgf\e\320k\260n\315u~\336\371M\t\235k\230S\375\311\303\240\351\037d\273\321y\335=K\016`_\317\230\2612_\023K\036\350\v\232\323Y\310\317_\035\227%\237\v\340\023\016\243\233\025\306:\227\351\370\364x\234\231\266\367\016w\275\333-\351\210}\375x\034\262\272kRuHa\362T/F!\347B\231O`K\304\037'k$$\245h)e\363\365mT\b\317\\2\361\026\351\254\375Jl1~\r\371\267\352\2322I\341\272\376\243^Un\266E7\230[VocUJ\220N\2116D/\025f=\213\314\325\vG}\311\360\377DT\307m\261&\263\340\272\243_\020\271rG^BW\210\030l\344\0324\335\233\300\023\272\225Im\330\n\227*Yv[\006\315\330y'\a\321\373\273A\240\305F{S\246I#/\355\2425\031\031GGF\270y\n\331\004\023G@\331\000\361\343\350\264$\032\355_\210y\000\205\342\375\212q\024\004\026W:\205 \363v?\035\270L-\270=\022\323\2003\v\336\277\t\237\356\374\n\267n\003\367\342\330;\371S\326\016`B6@Njm>\240\021%\336\345\002(P\204Yn\3279l\0228\264\254\304\2528t\372h\217\347sA\314\345\245\337)]\000\b\000\021\000\032\000\035\000+\0007\000Z\000m\000\264\000\000\000\000\000\000\002\001\000\000\000\000\000\000\000\t\000\000\000\000\000\000\000\000\000\000\000\000\000\000\002\270" }

  # The below is a binary plist containing a ShadowHashData key which CONTAINS
  # another binary plist. The nested binary plist contains a
  # 'SALTED-SHA512-PBKDF2' key that contains a base64 encoded salted-SHA512
  # password hash...
  let (:salted_sha512_pbkdf2_binary_plist) {"bplist00\321\001\002_\020\024SALTED-SHA512-PBKDF2\323\003\004\005\006\a\bWentropyTsaltZiterationsO\020\200x\352\320\334?$C\244\234?C\tt\222\233i\366\004\036\021\371&\315\313H&,\205q\366\271+\335}kL\005K\324t\004c \235\217\030\202\3361\353=\3715\322hEh\320H\017\312\0304n\"p'F\375\020r\300\005\235!2#7\237\351\030\036\202\246\224\362\e\215\236o8n\3268\334L\355\231\275[\372\223b\017\020O\314,\025\354T\302;\370\nB\316\274\2207\3163\214I\251\235p\aO\020 G|\323\303\032\3033\260L\206\025\222\372\345\221\263Q\375\200\f~j\255\224\034\227fW\206\266\323\035\021\017Z\b\v\")16A\304\347\000\000\000\000\000\000\001\001\000\000\000\000\000\000\000\t\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\352"}

  # The below is a base64 encoded salted-SHA512 password hash.
  let (:salted_sha512_pw_string) { "\335\006{\3744g@\377z\204\322\r\332t\021\330\n\003\246K\223\356\034!P\261\305t\035\346\352p\206\003n\247MMA\310\301Z<\366\246\023\0161W3\340\357\000\317T\t\301\311+\204\246L7\276\370\320*\245" }

  # And this is a base64 encoded salted-SHA512-PBKDF2 password hash.
  let (:salted_sha512_pbkdf2_pw_string) {"x\352\320\334?$C\244\234?C\tt\222\233i\366\004\036\021\371&\315\313H&,\205q\366\271+\335}kL\005K\324t\004c \235\217\030\202\3361\353=\3715\322hEh\320H\017\312\0304n\"p'F\375\020r\300\005\235!2#7\237\351\030\036\202\246\224\362\e\215\236o8n\3268\334L\355\231\275[\372\223b\017\020O\314,\025\354T\302;\370\nB\316\274\2207\3163\214I\251\235p\a"}

  # The below is a salted-SHA512 password hash in hex.
  let (:salted_sha512_hash) { 'dd067bfc346740ff7a84d20dda7411d80a03a64b93ee1c2150b1c5741de6ea7086036ea74d4d41c8c15a3cf6a6130e315733e0ef00cf5409c1c92b84a64c37bef8d02aa5' }

  # The below is a salted-SHA512-PBKDF2 password hash in hex.
  let (:salted_sha512_pbkdf2_hash) {'78ead0dc3f2443a49c3f430974929b69f6041e11f926cdcb48262c8571f6b92bdd7d6b4c054bd4740463209d8f1882de31eb3df935d2684568d0480fca18346e22702746fd1072c0059d213223379fe9181e82a694f21b8d9e6f386ed638dc4ced99bd5bfa93620f104fcc2c15ec54c23bf80a42cebc9037ce338c49a99d7007'}

  let (:salted_sha512_pbkdf2_salt_hex) {'477cd3c31ac333b04c861592fae591b351fd800c7e6aad941c97665786b6d31d'}

  let (:salted_sha512_pbkdf2_salt_binary) {"G|\323\303\032\3033\260L\206\025\222\372\345\221\263Q\375\200\f~j\255\224\034\227fW\206\266\323\035"}

  let (:salted_sha512_pbkdf2_iterations) {'3930'}

  let :plist_path do
    '/var/db/dslocal/nodes/Default/users/jeff.plist'
  end

  let :ds_provider do
    Puppet::Provider::NameService::DirectoryService
  end

  let :salted_sha512_shadow_hash_data do
    {'ShadowHashData' => [StringIO.new(salted_sha512_binary_plist)]}
  end

  let :salted_sha512_pbkdf2_shadow_hash_data do
    {'ShadowHashData' => [StringIO.new(salted_sha512_pbkdf2_binary_plist)]}
  end

  # In OS X versions 10.7 and 10.8, the user password is obtained by
  # reading the user's plist in /var/db/dslocal/nodes/Default/users/#{username}
  # and extracting a binary plist that's stored as the value of the
  # 'ShadowhashData' key. In the Directory Service provider, this binary
  # plist is converted to a Hash and stored in a variable called
  # 'converted_hash_plist'. The user password in 10.7 is stored as the
  # value of the 'SALTED-SHA512' key in the converted_hash_plist Hash.
  # In 10.8, new users have their PBKDF2 password data stored as the
  # value of the 'SALTED-SHA512-PBKDF2' key in the converted_hash_plist
  # Hash. It's also possible for users that were created in 10.7 to still
  # have a 'SALTED-SHA512' key in the converted_hash_plist when the machine
  # is upgraded to 10.8. The following two values are converted_hash_plist
  # Hash values formatted for 10.7 and 10.8 respectively.
  let :salted_sha512_converted_hash_plist do
    { 'SALTED-SHA512' => StringIO.new(salted_sha512_pw_string)
    }
  end

  let :salted_sha512_pbkdf2_converted_hash_plist do
    { 'SALTED-SHA512-PBKDF2' =>
      { 'salt'       => StringIO.new(salted_sha512_pbkdf2_salt_binary),
        'entropy'    => StringIO.new(salted_sha512_pbkdf2_pw_string),
        'iterations' => salted_sha512_pbkdf2_iterations
      }
    }
  end

  subject do
    Puppet::Provider::NameService::DirectoryService
  end

  let :provider do
    Puppet::Type.type(:user).provider(:directoryservice).new(stub('resource'))
  end

  it 'return the correct password when it is set on 10.7' do
    subject.expects(:get_macosx_version_major).returns('10.7').times(3)
    subject.expects(:get_shadowhashdata \
                   ).with('jeff').returns(salted_sha512_converted_hash_plist)
    subject.expects(:set_salted_sha512 \
                   ).with('jeff',                            \
                          salted_sha512_hash,                \
                          salted_sha512_converted_hash_plist \
                         ).returns(true)
    subject.set_password('jeff', 'uid', salted_sha512_hash)
    subject.get_password('uid', \
                         'jeff', \
                         salted_sha512_converted_hash_plist \
                        ).should == salted_sha512_hash
  end

  it 'return the correct salt value when it is set on 10.8' do
    subject.expects(:get_macosx_version_major).returns('10.8').times(2)
    subject.expects(:get_shadowhashdata \
                   ).with('jeff').returns(salted_sha512_pbkdf2_converted_hash_plist)
    subject.expects(:set_salted_sha512_pbkdf2 \
                   ).with('jeff',                                   \
                          'entropy',                                \
                          salted_sha512_pbkdf2_hash,                \
                          salted_sha512_pbkdf2_converted_hash_plist \
                         ).returns(true)
    subject.set_password('jeff', 'uid', salted_sha512_pbkdf2_hash)
    subject.get_salt('jeff',                                   \
                     salted_sha512_pbkdf2_converted_hash_plist \
                    ).should == salted_sha512_pbkdf2_salt_hex
  end

  it 'fail if Puppet attempts to set the salt property on a version of OS X
      that is < 10.8' do
    provider.class.expects(:get_macosx_version_major).returns('10.6')
    expect {
      provider.salt = 'saltvalue'
    }.to raise_error RuntimeError, /The salt property is only available on versions of OS X > 10\.7/
  end

  it 'fail if Puppet attempts to set the iterations property on a version of OS X
      that is < 10.8' do
    provider.class.expects(:get_macosx_version_major).returns('10.6')
    expect {
      provider.iterations = '10000'
    }.to raise_error RuntimeError, /The iterations property is only available on versions of OS X > 10\.7/
  end

  it 'return the correct iterations value when it is set on 10.8' do
    subject.expects(:get_macosx_version_major).returns('10.8').times(2)
    subject.expects(:get_shadowhashdata \
                   ).with('jeff').returns(salted_sha512_pbkdf2_converted_hash_plist)
    subject.expects(:set_salted_sha512_pbkdf2 \
                   ).with('jeff',                                   \
                          'entropy',                                \
                          salted_sha512_pbkdf2_hash,                \
                          salted_sha512_pbkdf2_converted_hash_plist \
                         ).returns(true)
    subject.set_password('jeff', 'uid', salted_sha512_pbkdf2_hash)
    subject.get_iterations('jeff',                             \
                     salted_sha512_pbkdf2_converted_hash_plist \
                    ).should == Integer(salted_sha512_pbkdf2_iterations)
  end

  it 'return the correct password when it is set on 10.8' do
    subject.expects(:get_macosx_version_major).returns('10.8').times(3)
    subject.expects(:get_shadowhashdata \
                   ).with('jeff').returns(salted_sha512_pbkdf2_converted_hash_plist)
    subject.expects(:set_salted_sha512_pbkdf2 \
                   ).with('jeff',                                   \
                          'entropy',                                \
                          salted_sha512_pbkdf2_hash,                \
                          salted_sha512_pbkdf2_converted_hash_plist \
                         ).returns(true)
    subject.set_password('jeff', 'uid', salted_sha512_pbkdf2_hash)
    subject.get_password('uid',                                    \
                         'jeff',                                   \
                         salted_sha512_pbkdf2_converted_hash_plist \
                        ).should == salted_sha512_pbkdf2_hash
  end

  it 'execute get_salted_sha512 if a 10.7-style password hash exists
      for a user and the get_password method is called' do
    subject.expects(:get_macosx_version_major).returns('10.7')
    subject.expects(:get_salted_sha512
                   ).with(salted_sha512_converted_hash_plist
                         ).returns(salted_sha512_hash)
    subject.get_password('uid', 'jeff', salted_sha512_converted_hash_plist)
  end

  it 'execute get_salted_sha512_pbkdf2 when getting the password on
      10.8' do
    subject.expects(:get_macosx_version_major).returns('10.8')
    subject.expects(:get_salted_sha512_pbkdf2 \
                   ).with(salted_sha512_pbkdf2_converted_hash_plist, \
                          'entropy'                                  \
                         ).returns(salted_sha512_pbkdf2_hash)
    subject.get_password('uid', 'jeff', salted_sha512_pbkdf2_converted_hash_plist)
  end

  it 'return the 10.7-style password hash if it exists for a user on a 10.8
      machine and the get_password method is called' do
    subject.expects(:get_macosx_version_major).returns('10.8')
    subject.expects(:get_salted_sha512 \
                   ).with(salted_sha512_converted_hash_plist
                         ).returns(salted_sha512_hash)
    subject.get_password('uid', 'jeff', salted_sha512_converted_hash_plist)
  end

  it 'fail if a salted-SHA512 password hash is not passed in 10.7' do
    subject.expects(:get_macosx_version_major).returns('10.7').twice
    expect {
      subject.set_password('jeff', 'uid', 'badpassword')
    }.to raise_error(RuntimeError, /OS X 10.7 requires a Salted SHA512 hash password of 136 characters./)
  end

  it 'fail if a salted-SHA512-PBKDF2 password hash is not passed
      in 10.8' do
    subject.expects(:get_macosx_version_major).returns('10.8').times(2)
    expect {
      subject.set_password('jeff', 'uid', 'wrongpassword')
    }.to raise_error(RuntimeError, \
                         /OS X versions > 10.7 require a Salted SHA512 PBKDF2 password hash of 256 characters/)
  end

  it 'do not attempt to get an \'iterations\' value when passed
      a converted_hash_plist that contains a \'SALTED-SHA512\' key' do
    subject.expects(:get_salted_sha512_pbkdf2).never
    subject.get_iterations('jeff', salted_sha512_converted_hash_plist \
                    ).should == nil

  end

  it 'return an \'iterations\' value when passed a converted_hash_plist
      that contains a \'SALTED-SHA512-PBKDF2\' key' do
    subject.expects(:get_salted_sha512_pbkdf2 \
                   ).with(salted_sha512_pbkdf2_converted_hash_plist, \
                          'iterations').returns(true)
    subject.get_iterations('jeff', salted_sha512_pbkdf2_converted_hash_plist)
  end

  it 'do not attempt to get a \'salt\' value when passed a
      converted_hash_plist that contains a \'SALTED-SHA512\' key' do
    subject.expects(:get_salted_sha512_pbkdf2).never
    subject.get_salt('jeff', salted_sha512_converted_hash_plist \
                    ).should == nil

  end

  it 'return a \'salt\' value when passed a converted_hash_plist
      that contains a \'SALTED-SHA512-PBKDF2\' key' do
    subject.expects(:get_salted_sha512_pbkdf2 \
                   ).with(salted_sha512_pbkdf2_converted_hash_plist, \
                          'salt').returns(true)
    subject.get_salt('jeff', salted_sha512_pbkdf2_converted_hash_plist)
  end

  it 'call set_salted_sha512 on 10.7 when setting the password' do
    subject.expects(:get_macosx_version_major).returns('10.7').times(2)
    subject.expects(:get_shadowhashdata \
                   ).with('jeff').returns(salted_sha512_converted_hash_plist)
    subject.expects(:set_salted_sha512 \
                   ).with('jeff',                            \
                          salted_sha512_hash,                \
                          salted_sha512_converted_hash_plist \
                         ).returns(true)
    subject.set_password('jeff', 'uid', salted_sha512_hash)
  end

  it 'call set_salted_sha512_pbkdf2 on 10.8 when setting the password' do
    subject.expects(:get_macosx_version_major).returns('10.8').times(2)
    subject.expects(:get_shadowhashdata \
                   ).with('jeff').returns(salted_sha512_pbkdf2_converted_hash_plist)
    subject.expects(:set_salted_sha512_pbkdf2 \
                   ).with('jeff',                                   \
                          'entropy',                                \
                          salted_sha512_pbkdf2_hash,                \
                          salted_sha512_pbkdf2_converted_hash_plist \
                         ).returns(true)
    subject.set_password('jeff', 'uid', salted_sha512_pbkdf2_hash)
  end

  it 'delete the SALTED-SHA512 key and call set_salted_sha512_pbkdf2 if a
      10.7-style user password exists on a 10.8 machine and a 10.8-style
      password is enforced' do
    subject.expects(:get_macosx_version_major).returns('10.8').times(2)
    subject.expects(:get_shadowhashdata \
                   ).with('jeff').returns(salted_sha512_converted_hash_plist)
    # The empty hash as the last argument of set_salted_sha512_pbkdf2
    # tests whether Hash.delete gets performed on the converted_hash_plist
    subject.expects(:set_salted_sha512_pbkdf2 \
                   ).with('jeff',                                   \
                          'entropy',                                \
                          salted_sha512_pbkdf2_hash,                \
                          {}
                         ).returns(true)
    subject.set_password('jeff', 'uid', salted_sha512_pbkdf2_hash)
  end

  it 'fail if the OS X Users plist does not exist' do
    File.expects(:exists?).with(plist_path).returns false
    expect {
      subject.get_shadowhashdata('jeff')
    }.to raise_error(RuntimeError, /jeff.plist is not readable/)
  end

  it 'fail if the OS X Users plist is not readable' do
    File.expects(:exists?).with(plist_path).returns true
    File.expects(:readable?).with(plist_path).returns false
    expect {
      subject.get_shadowhashdata('jeff')
    }.to raise_error(RuntimeError, /jeff.plist is not readable/)
  end

  it 'call convert_binary_to_xml if a correct Users plist is passed' do
    File.expects(:exists?).with(plist_path).returns true
    File.expects(:readable?).with(plist_path).returns true
    Plist.expects(:parse_xml \
                 ).returns(salted_sha512_pbkdf2_shadow_hash_data)
    subject.expects(:convert_binary_to_xml \
                   ).with(salted_sha512_pbkdf2_binary_plist).returns(true)
    subject.expects(:plutil).returns true
    subject.get_shadowhashdata('jeff')
  end

  it 'return false if the Users plist lacks a ShadowHashData field' do
    File.expects(:exists?).with(plist_path).returns true
    File.expects(:readable?).with(plist_path).returns true
    Plist.expects(:parse_xml \
                 ).returns({'nothing' => 'set'})
    subject.expects(:plutil).returns true
    subject.get_shadowhashdata('jeff').should == false
  end

end

describe '(#4855) directoryservice group resource failure' do
  let :provider_class do
    Puppet::Type.type(:group).provider(:directoryservice)
  end

  let :group_members do
    ['root','jeff']
  end

  let :user_account do
    ['root']
  end

  let :stub_resource do
    stub('resource')
  end

  subject do
    provider_class.new(stub_resource)
  end

  before :each do
    @resource = stub("resource")
    @provider = provider_class.new(@resource)
  end

  it 'delete a group member if the user does not exist' do
    stub_resource.stubs(:[]).with(:name).returns('fake_group')
    stub_resource.stubs(:name).returns('fake_group')
    subject.expects(:execute).with([:dseditgroup, '-o', 'edit', '-n', '.',
                                   '-d', 'jeff',
                                   'fake_group']).raises(Puppet::ExecutionFailure,
                                   'it broke')
    subject.expects(:execute).with([:dscl, '.', '-delete',
                                   '/Groups/fake_group', 'GroupMembership',
                                   'jeff'])
    subject.remove_unwanted_members(group_members, user_account)
  end
end


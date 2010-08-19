require 'helper'

class TestEutils < Test::Unit::TestCase
  tool = "eutilstest"
  email = "seouri@gmail.com"
  eutils = Eutils.new(tool, email)
  should "set tool and email at instance creation" do
    assert_equal eutils.tool, tool
    assert_equal eutils.email, email
  end

  should "set tool and email after instance creation" do
    eutils_no_tool_email = Eutils.new
    eutils_no_tool_email.tool = tool
    eutils_no_tool_email.email = email
    assert_equal eutils_no_tool_email.tool, tool
    assert_equal eutils_no_tool_email.email, email
  end

  should "raise runtime error without tool or email" do
    eutils_no = Eutils.new
    assert_raise RuntimeError do
      eutils_no.einfo
    end
  end

  should "get array of db names from EInfo with no parameter" do
    db = eutils.einfo
    assert_equal Array, db.class
    assert_equal true, db.include?("pubmed")
    assert_equal Array, eutils.einfo("").class
    assert_equal Array, eutils.einfo("  ").class
  end

  should "get hash from EInfo with db parameter" do
    i = eutils.einfo("pubmed")
    assert_equal Hash, i.class
    assert_equal :eInfoResult, i.keys.first
    assert_equal "pubmed", i[:eInfoResult][:DbInfo][:DbName]
  end
end

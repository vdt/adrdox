module adrdox.main;

string skeletonFile = "skeleton.html";
string outputDirectory = "generated-docs";

/*

Glossary feature: little short links that lead somewhere else.


	FIXME: it should be able to handle bom. consider core/thread.d the unittest example is offset.


	FIXME:
		* make sure there's a link to the source for everything
		* search
		* package index without needing to build everything at once
		* version specifiers
		* fix spurious extern(C) etc (see std.stdio.write)
		* prettified constraints
*/

import dparse.parser;
import dparse.lexer;
import dparse.ast;

import arsd.dom;
import arsd.docgen.comment;

import std.algorithm :sort, canFind;

import std.string;
import std.conv : to;

// FIXME: make See Also automatically list dittos that are not overloads

enum skip_undocumented = true;

static bool sorter(Decl a, Decl b) {
	if(a.declarationType == b.declarationType)
		return a.name < b.name;
	else if(a.declarationType == "module" || b.declarationType == "module") // always put modules up top
		return 
			(a.declarationType == "module" ? "aaaaaa" : a.declarationType)
			< (b.declarationType == "module" ? "aaaaaa" : b.declarationType);
	else
		return a.declarationType < b.declarationType;
}

void annotatedPrototype(T)(T decl, MyOutputRange output) {
	static if(is(T == TemplateDecl)) {
		auto td = cast(TemplateDecl) decl;
		auto epony = td.eponymousMember;
		if(epony) {
			if(auto e = cast(FunctionDecl) epony) {
				doFunctionDec(e, output);
				return;
			}
		}
	}


	auto classDec = decl.astNode;

	auto f = new MyFormatter!(typeof(output))(output, decl);

	void writePrototype() {
		output.putTag("<div class=\"aggregate-prototype\">");

		if(decl.parent !is null && !decl.parent.isModule) {
			output.putTag("<div class=\"parent-prototype\">");
			decl.parent.getSimplifiedPrototype(output);
			output.putTag("</div><div>");
		}

		writeAttributes(f, output, decl.attributes);

		output.putTag("<span class=\"builtin-type\">");
		output.put(decl.declarationType);
		output.putTag("</span>");
		output.put(" ");
		output.put(decl.name);
		output.put(" ");

		foreach(idx, ir; decl.inheritsFrom()) {
			if(idx == 0)
				output.put(" : ");
			else
				output.put(", ");
			if(ir.decl is null)
				f.format(ir.ast);
			else
				output.putTag(`<a class="xref parent-class" href=`~ir.decl.link~`>`~ir.decl.name~`</a> `);
		}

		if(classDec.templateParameters)
			f.format(classDec.templateParameters);
		if(classDec.constraint)
			f.format(classDec.constraint);

		// FIXME: invariant

		output.put(" {");
		foreach(child; decl.children) {
			if(child.isPrivate())
				continue;
			// I want to show undocumented plain data members (if not private)
			// since they might be used as public fields or in ctors for simple
			// structs, but I'll skip everything else undocumented.
			if(!child.isDocumented() && (cast(VariableDecl) child) is null)
				continue;
			output.putTag("<div class=\"aggregate-member\">");
			if(child.isDocumented())
				output.putTag("<a href=\""~child.link~"\"");
			child.getAggregatePrototype(output);
			if(child.isDocumented())
				output.putTag("</a>");
			output.putTag("</div>");
		}
		output.put("}");

		if(decl.parent !is null && !decl.parent.isModule) {
			output.putTag("</div>");
		}

		output.putTag("</div>");
	}


	writeOverloads!writePrototype(decl, output);
}


	void doEnumDecl(T)(T decl, Element content)
	{
		auto enumDec = decl.astNode;
		static if(is(typeof(enumDec) == const(AnonymousEnumDeclaration))) {
			if(enumDec.members.length == 0) return;
			auto name = enumDec.members[0].name.text;
			auto type = enumDec.baseType;
			auto members = enumDec.members;
		} else {
			auto name = enumDec.name.text;
			auto type = enumDec.type;
			const(EnumMember)[] members;
			if(enumDec.enumBody)
				members = enumDec.enumBody.enumMembers;
		}

		static if(is(typeof(enumDec) == const(AnonymousEnumDeclaration))) {
			// undocumented anonymous enums get a pass if any of
			// their members are documented because that's what dmd does...
			// FIXME maybe

			bool foundOne = false;
			foreach(member; members) {
				if(member.comment.length) {
					foundOne = true;
					break;
				}
			}

			if(!foundOne && skip_undocumented)
				return;
		} else {
			if(enumDec.comment.length == 0 && skip_undocumented)
				return;
		}

		/*
		auto f = new MyFormatter!(typeof(output))(output);

		if(type) {
			output.putTag("<div class=\"base-type\">");
			f.format(type);
			output.putTag("</div>");
		}
		*/

		content.addChild("h2", "Values").attrs.id = "values";

		auto table = content.addChild("table").addClass("enum-members");
		table.appendHtml("<tr><th>Value</th><th>Meaning</th></tr>");

		foreach(member; members) {
			auto memberComment = formatDocumentationComment(preprocessComment(member.comment), decl);
			auto tr = table.addChild("tr");
			tr.addClass("enum-member");
			tr.attrs.id = member.name.text;

			auto td = tr.addChild("td");

			if(member.type) {
				td.addChild("span", toHtml(member.type)).addClass("enum-type");
			}

			td.addChild("a", member.name.text, "#" ~ member.name.text).addClass("enum-member-name");

			if(member.assignExpression) {
				td.addChild("span", toHtml(member.assignExpression)).addClass("enum-member-value");
			}
			// type
			// assignExpression
			td = tr.addChild("td");
			td.innerHTML = memberComment;

			// I might write to parent list later if I can do it all semantically inside the anonymous enum
			// since these names are introduced into the parent scope i think it is justified to list them there
			// maybe.
		}
	}


	void doFunctionDec(T)(T decl, MyOutputRange output)
	{
		auto functionDec = decl.astNode;

		//if(!decl.isDocumented() && skip_undocumented)
			//return;

		string[] conceptsFound;

		auto f = new MyFormatter!(typeof(output))(output, decl);

		/+

		auto comment = parseDocumentationComment(dittoSupport(functionDec, functionDec.comment), fullyQualifiedName ~ name);

		if(auto ptr = name in overloadChain[$-1]) {
			*ptr += 1;
			name ~= "." ~ to!string(*ptr);
		} else {
			overloadChain[$-1][name] = 1;
			overloadNodeChain[$-1] = cast() functionDec;
		}

		const(ASTNode)[] overloadsList;

		if(auto overloads = overloadNodeChain[$-1] in additionalModuleInfo.overloadsOf) {
			overloadsList = *overloads;
		}

		if(dittoChain[$-1])
		if(auto dittos = dittoChain[$-1] in additionalModuleInfo.dittos) {
			auto list = *dittos;
			outer: foreach(item; list) {
				if(item is functionDec)
					continue;

				// already listed as a formal overload which means we
				// don't need to list it again under see also
				foreach(ol; overloadsList)
					if(ol is item)
						continue outer;

				string linkHtml;
				linkHtml ~= `<a href="`~htmlEncode(linkMapping[item])~`">` ~ htmlEncode(nameMapping[item]) ~ `</a>`;

				comment.see_alsos ~= linkHtml;
			}
		}

		descendInto(name);

		output.putTag("<h1><span class=\"entity-name\">" ~ name ~ "</span> "~typeString~"</h1>");

		writeBreadcrumbs();

		output.putTag("<div class=\"function-declaration\">");

		comment.writeSynopsis(output);
		+/

		void writeFunctionPrototype() {
			string outputStr;
			auto originalOutput = output;

			MyOutputRange output = MyOutputRange(&outputStr);
			auto f = new MyFormatter!(typeof(output))(output);

			output.putTag("<div class=\"function-prototype\">");

			output.putTag(`<a href="http://dpldocs.info/reading-prototypes" id="help-link">?</a>`);

			if(decl.parent !is null && !decl.parent.isModule) {
				output.putTag("<div class=\"parent-prototype\">");
				decl.parent.getSimplifiedPrototype(output);
				output.putTag("</div><div>");
			}

			writeAttributes(f, output, decl.attributes);


			static if(
				!is(typeof(functionDec) == const(Constructor)) &&
				!is(typeof(functionDec) == const(Postblit)) &&
				!is(typeof(functionDec) == const(Destructor))
			) {
				output.putTag("<div class=\"return-type\">");

				if (functionDec.hasAuto && functionDec.hasRef)
					output.putTag(`<a class="lang-feature" href="http://dpldocs.info/auto-ref-function-return-prototype">auto ref</a> `);
				else {
					if (functionDec.hasAuto)
						output.putTag(`<a class="lang-feature" href="http://dpldocs.info/auto-function-return-prototype">auto</a> `);
					if (functionDec.hasRef)
						output.putTag(`<a class="lang-feature" href="http://dpldocs.info/ref-function-return-prototype">ref</a> `);
				}

				if (functionDec.returnType !is null)
					f.format(functionDec.returnType);

				output.putTag("</div>");
			}

			output.putTag("<div class=\"function-name\">");
			output.put(decl.name);
			output.putTag("</div>");

			foreach(attr; decl.astNode.memberFunctionAttributes) {
				f.format(attr);
				output.put(" ");
			}

			output.putTag("<div class=\"template-parameters\">");
			if (functionDec.templateParameters !is null)
				f.format(functionDec.templateParameters);
			output.putTag("</div>");
			output.putTag("<div class=\"runtime-parameters\">");
			f.format(functionDec.parameters);
			output.putTag("</div>");
			if(functionDec.constraint !is null) {
				output.putTag("<div class=\"template-constraint\">");
				f.format(functionDec.constraint);
				output.putTag("</div>");
			}
			if(functionDec.functionBody !is null) {
				// FIXME: list inherited contracts
				output.putTag("<div class=\"function-contracts\">");
				import dparse.formatter;
				auto f2 = new Formatter!(typeof(output))(output);

				if(functionDec.functionBody.inStatement) {
					output.putTag("<div class=\"in-contract\">");
					f2.format(functionDec.functionBody.inStatement);
					output.putTag("</div>");
				}
				if(functionDec.functionBody.outStatement) {
					output.putTag("<div class=\"out-contract\">");
					f2.format(functionDec.functionBody.outStatement);
					output.putTag("</div>");
				}

				output.putTag("</div>");
			}
			//output.put(" : ");
			//output.put(to!string(functionDec.name.line));


			if(decl.parent !is null && !decl.parent.isModule) {
				output.putTag("</div>");
				decl.parent.writeTemplateConstraint(output);
			}

			output.putTag("</div>");

			originalOutput.putTag(linkUpHtml(outputStr, decl));
		}


		writeOverloads!writeFunctionPrototype(decl, output);
	}

	void writeOverloads(alias writePrototype, D : Decl)(D decl, ref MyOutputRange output) {
		auto overloadsList = decl.getImmediateDocumentedOverloads();

		// I'm treating dittos similarly to overloads
		if(overloadsList.length == 1) {
			overloadsList = decl.getDittos();
		} else {
			foreach(ditto; decl.getDittos()) {
				if(!overloadsList.canFind(ditto))
					overloadsList ~= ditto;
			}
		}
		if(overloadsList.length > 1) {
			import std.conv;
			output.putTag("<ol class=\"overloads\">");
			foreach(idx, item; overloadsList) {
				assert(item.parent !is null);
				string cn;
				Decl epony;
				if(auto t = cast(TemplateDecl) item)
					epony = t.eponymousMember;

				if(item !is decl && decl !is epony)
					cn = "overload-option";
				else
					cn = "active-overload-option";

				if(item.name != decl.name)
					cn ~= " ditto-option";

				output.putTag("<li class=\""~cn~"\">");

				//if(item is decl)
					//writeFunctionPrototype();
				//} else {
				{
					if(item !is decl)
						output.putTag(`<a href="`~item.link~`">`);

					output.putTag("<span class=\"overload-signature\">");
					item.getSimplifiedPrototype(output);
					output.putTag("</span>");
					if(item !is decl)
						output.putTag(`</a>`);
				}

				if(item is decl || decl is epony)
					writePrototype();

				output.putTag("</li>");
			}
			output.putTag("</ol>");
		} else {
			writePrototype();
		}
	}


	void writeAttributes(F, W)(F formatter, W writer, const(VersionOrAttribute)[] attrs)
	{
		writer.putTag("<div class=\"attributes\">");
		IdType protection;
		foreach (a; attrs)
		{
			if (a.attr && isProtection(a.attr.attribute.type))
				protection = a.attr.attribute.type;
		}
		switch (protection)
		{
		case tok!"private": writer.put("private "); break;
		case tok!"package": writer.put("package "); break;
		case tok!"protected": writer.put("protected "); break;
		case tok!"export": writer.put("export "); break;
		case tok!"public": // see below
		default:
			// I'm not printing public so this is commented intentionally
			// public is the default state of documents so saying it outright
			// is kinda just a waste of time IMO.
			//writer.put("public ");
		break;
		}
		foreach (a; attrs)
		{
			if(auto fakeAttr = cast(FakeAttribute) a) {
				writer.putTag(fakeAttr.toHTML());
				continue;
			}
			// skipping auto because it is already handled as the return value
			if (!isProtection(a.attr.attribute.type) && a.attr.attribute.type != tok!"auto")
			{
				formatter.format(a.attr);
				writer.put(" ");
			}
		}
		writer.putTag("</div>");
	}

class VersionOrAttribute {
	const(Attribute) attr;
	this(const(Attribute) attr) {
		this.attr = attr;
	}

	const(VersionOrAttribute) invertedClone() const {
		return new VersionOrAttribute(attr);
	}
}

class FakeAttribute : VersionOrAttribute {
	this() { super(null); }
	abstract string toHTML() const;
}

class VersionFakeAttribute : FakeAttribute {
	string cond;
	bool inverted;
	this(string condition, bool inverted = false) {
		cond = condition;
		this.inverted = inverted;
	}

	override const(VersionFakeAttribute) invertedClone() const {
		return new VersionFakeAttribute(cond, !inverted);
	}

	override string toHTML() const {
		auto element = Element.make("span");
		element.addChild("span", "version", "lang-feature");
		element.appendText("(");
		if(inverted)
			element.appendText("!");
		element.addChild("span", cond);
		element.appendText(")");
		return element.toString;
	}
}

void putSimplfiedReturnValue(MyOutputRange output, const FunctionDeclaration decl) {
	if (decl.hasAuto && decl.hasRef)
		output.putTag(`<span class="lang-feature">auto ref</span> `);
	else {
		if (decl.hasAuto)
			output.putTag(`<span class="lang-feature">auto</span> `);
		if (decl.hasRef)
			output.putTag(`<span class="lang-feature">ref</span> `);
	}

	if (decl.returnType !is null)
		output.putTag(toHtml(decl.returnType).source);
}

void putSimplfiedArgs(T)(MyOutputRange output, const T decl) {
	// FIXME: do NOT show default values here
	if(decl.parameters)
		output.putTag(toHtml(decl.parameters).source);

}


Document writeHtml(Decl decl, bool forReal = true) {
	if(decl.isPrivate() || !decl.isDocumented())
		return null;

	auto title = decl.name;
	bool justDocs = false;
	if(auto mod = cast(ModuleDecl) decl) {
		if(mod.justDocsTitle !is null) {
			title = mod.justDocsTitle;
			justDocs = true;
		}
	}

	if(decl.parent !is null && !decl.parent.isModule) {
		title = decl.parent.name ~ "." ~ title;
	}

	auto document = new Document();
	import std.file;
	document.parseUtf8(readText(skeletonFile), true, true);
	document.title = title ~ " (" ~ decl.fullyQualifiedName ~ ")";

	auto content = document.requireElementById("page-content");

	auto comment = decl.parsedDocComment;

	content.addChild("h1", title);

	auto breadcrumbs = content.addChild("div").addClass("breadcrumbs");

	//breadcrumbs.prependChild(Element.make("a", decl.name, decl.link).addClass("current breadcrumb"));

	{
		auto p = decl.parent;
		while(p) {
			// cut off package names that would be repeated
			auto name = (p.isModule && p.parent) ? lastDotOnly(p.name) : p.name;
			breadcrumbs.prependChild(Element.make("a", name, p.link).addClass("breadcrumb"));
			p = p.parent;
		}
	}

	string s;
	MyOutputRange output = MyOutputRange(&s);

	comment.writeSynopsis(output);
	content.addChild("div", Html(s));

	s = null;
	decl.getAnnotatedPrototype(output);
	content.addChild("div", Html(s), "annotated-prototype");

	Element lastDt;
	string dittoedName;
	string dittoedComment;

	void handleChildDecl(Element dl, Decl child) {
		auto cc = child.parsedDocComment;
		string sp;
		MyOutputRange or = MyOutputRange(&sp);
		child.getSimplifiedPrototype(or);

		auto printableName = child.name;
		if(child.isModule && child.parent && child.parent.isModule) {
			if(printableName.startsWith(child.parent.name))
				printableName = printableName[child.parent.name.length + 1 .. $];
		}

		auto newDt = Element.make("dt", Element.make("a", printableName, child.link));
		auto st = newDt.addChild("div", Html(sp)).addClass("simplified-prototype");
		st.style.maxWidth = to!string(st.innerText.length * 11 / 10) ~ "ch";

		if(child.isDitto && child.comment == dittoedComment && lastDt !is null) {
			// ditto'd names don't need to be written again
			if(child.name == dittoedName) {
				if(sp == lastDt.requireSelector(".simplified-prototype").innerHTML)
					return; // no need to say the same thing twice
				// same name, but different prototype. Cut the repetition.
				newDt.requireSelector("a").removeFromTree();
			}
			lastDt.addSibling(newDt);
		} else {
			dl.addChild(newDt);
			dl.addChild("dd", Html(formatDocumentationComment(cc.ddocSummary, child)));
			dittoedComment = child.comment;
		}

		lastDt = newDt;
		dittoedName = child.name;
	}

	Decl[] ctors;
	Decl[] members;
	Decl[] submodules;

	if(forReal)
	foreach(child; decl.children) {
		if(child.isPrivate() || !child.isDocumented())
			continue;
		if(child.isConstructor())
			ctors ~= child;
		else if(child.isModule)
			submodules ~= child;
		else if(cast(DestructorDecl) child)
			 {} // intentionally blank
		else if(cast(PostblitDecl) child)
			 {} // intentionally blank
		else
			members ~= child;
	}

	if(decl.disabledDefaultConstructor) {
		content.addChild("h2", "Disabled Default Constructor").id = "disabled-default-constructor";
		auto div = content.addChild("div");
		div.addChild("p", "A disabled default is present on this object. To use it, use one of the other constructors or a factory function.");
	}

	if(ctors.length) {
		content.addChild("h2", "Constructors").id = "constructors";
		auto dl = content.addChild("dl").addClass("member-list constructors");

		foreach(child; ctors) {
			if(child is decl.disabledDefaultConstructor)
				continue;
			handleChildDecl(dl, child);
			writeHtml(child);
		}
	}

	if(auto dtor = decl.destructor) {
		content.addChild("h2", "Destructor").id = "destructor";
		auto dl = content.addChild("dl").addClass("member-list");

		if(dtor.isDocumented)
			handleChildDecl(dl, dtor);
		else
			content.addChild("p", "A destructor is present on this object, but not explicitly documented in the source.");
		//writeHtml(dtor);
	}

	if(auto postblit = decl.postblit) {
		content.addChild("h2", "Postblit").id = "postblit";
		auto dl = content.addChild("dl").addClass("member-list");

		if(postblit.isDisabled())
			content.addChild("p", "Copying this object is disabled.");

		if(postblit.isDocumented)
			handleChildDecl(dl, postblit);
		else
			content.addChild("p", "A postblit is present on this object, but not explicitly documented in the source.");
		//writeHtml(dtor);
	}


	if(submodules.length) {
		content.addChild("h2", "Modules").id = "modules";
		auto dl = content.addChild("dl").addClass("member-list native");
		foreach(child; submodules.sort!((a,b) => a.name < b.name)) {
			handleChildDecl(dl, child);

			writeHtml(child);
		}
	}

	if(auto at = decl.aliasThis) {
		content.addChild("h2", "Alias This").id = "alias-this";
		auto div = content.addChild("div");

		div.addChild("a", at.name, at.link);

		if(decl.aliasThisComment.length) {
			auto memberComment = formatDocumentationComment(preprocessComment(decl.aliasThisComment), decl);
			auto dc = div.addChild("div").addClass("documentation-comment");
			dc.innerHTML = memberComment;
		}
	}

	if(members.length) {
		content.addChild("h2", "Members").id = "members";
		Element dl;
		string lastType;
		foreach(child; members.sort!sorter) {
			if(child.declarationType != lastType) {
				content.addChild("h3", pluralize(child.declarationType).capitalize);
				dl = content.addChild("dl").addClass("member-list native");
				lastType = child.declarationType;
			}

			handleChildDecl(dl, child);

			writeHtml(child);
		}
	}

	auto irList = decl.inheritsFrom;
	if(irList.length) {
		auto h2 = content.addChild("h2", "Inherited Members");
		h2.id = "inherited-members";

		bool hasAnyListing = false;

		foreach(ir; irList) {
			if(ir.decl is null) continue;
			auto h3 = content.addChild("h3", "From " ~ ir.decl.name);
			h3.id = "inherited-from-" ~ ir.decl.fullyQualifiedName;
			auto dl = content.addChild("dl").addClass("member-list inherited");
			bool hadListing = false;
			foreach(child; ir.decl.children) {
				if(child.isPrivate() || !child.isDocumented())
					continue;
				if(!child.isConstructor()) {
					handleChildDecl(dl, child);
					hadListing = true;
					hasAnyListing = true;
				}
			}

			if(!hadListing) {
				h3.removeFromTree();
				dl.removeFromTree();
			}
		}

		if(!hasAnyListing)
			h2.removeFromTree();
	}


	decl.addSupplementalData(content);

	s = null;

	if(auto fd = cast(FunctionDeclaration) decl.getAstNode())
		comment.writeDetails(output, fd, decl.getProcessedUnittests());
	else if(auto fd = cast(Constructor) decl.getAstNode())
		comment.writeDetails(output, fd, decl.getProcessedUnittests());
	else if(auto fd = cast(TemplateDeclaration) decl.getAstNode())
		comment.writeDetails(output, fd, decl.getProcessedUnittests());
	else if(auto fd = cast(AliasDecl) decl) {
		if(fd.initializer)
			comment.writeDetails(output, fd.initializer, decl.getProcessedUnittests());
		else
			comment.writeDetails(output, decl, decl.getProcessedUnittests());
	} else
		comment.writeDetails(output, decl, decl.getProcessedUnittests());

	content.addChild("div", Html(s));

	if(forReal) {
		auto nav = document.requireElementById("page-nav");

		Decl[] navArray;
		string[string] inNavArray;
		if(decl.parent) {
			foreach(child; decl.parent.children) {
				if(!child.isPrivate() && child.isDocumented()) {
					// strip overloads from sidebar
					if(child.name !in inNavArray) {
						navArray ~= child;
						inNavArray[child.name] = "";
					}
				}
			}
		} else {
		/+ commented pending removal
			// this is for building the module nav when doing an incremental
			// rebuild. It loads the index.xml made with the special option below.
			static bool attemptedXmlLoad;
			static ModuleDecl[] indexedModules;
			if(!attemptedXmlLoad) {
				import std.file;
				if(std.file.exists("index.xml")) {
					auto idx = new XmlDocument(readText("index.xml"));
					foreach(d; idx.querySelectorAll("listing > decl"))
						indexedModules ~= new ModuleDecl(d.requireSelector("name").innerText);
				}
				attemptedXmlLoad = true;
			}

			auto tm = cast(ModuleDecl) decl;
			if(tm !is null)
			foreach(im; indexedModules)
				if(im.packageName == tm.packageName)
					navArray ~= im;
		+/
		}

		{
			auto p = decl.parent;
			while(p) {
				// cut off package names that would be repeated
				auto name = (p.isModule && p.parent) ? lastDotOnly(p.name) : p.name;
				nav.prependChild(Element.make("a", name, p.link)).addClass("parent");
				p = p.parent;
			}
		}

		import std.algorithm;

		sort!sorter(navArray);

		Element list;

		string lastType;
		foreach(item; navArray) {
			if(item.declarationType != lastType) {
				nav.addChild("span", pluralize(item.declarationType)).addClass("type-separator");
				list = nav.addChild("ul");
				lastType = item.declarationType;
			}

			// cut off package names that would be repeated
			auto name = (item.isModule && item.parent) ? lastDotOnly(item.name) : item.name;
			auto n = list.addChild("li").addChild("a", name, item.link).addClass(item.declarationType.replace(" ", "-"));
			if(item.name == decl.name)
				n.addClass("current");
		}

		if(justDocs) {
			if(auto d = document.querySelector("#details"))
				d.removeFromTree;
		}

		auto toc = Element.make("div");
		toc.id = "table-of-contents";
		auto current = toc;
		int lastLevel;
		tree: foreach(header; document.root.tree) {
			int level;
			switch(header.tagName) {
				case "h2":
					level = 2;
				break;
				case "h3":
					level = 3;
				break;
				case "h4":
					level = 4;
				break;
				case "h5:":
					level = 5;
				break;
				case "h6":
					level = 6;
				break;
				default: break;
			}

			if(level == 0) continue;

			auto parentCheck = header;
			while(parentCheck) {
				if(parentCheck.hasClass("adrdox-sample"))
					continue tree;
				parentCheck = parentCheck.parentNode;
			}

			if(level > lastLevel) {
				current = current.addChild("ol");
				current.addClass("heading-level-" ~ to!string(level));
			} else if(level < lastLevel) {
				while(current && !current.hasClass("heading-level-" ~ to!string(level)))
					current = current.parentNode;
				if(current is null) {
					import std.stdio;
					writeln("WARNING: TOC broken on " ~ decl.name);
					goto skip_toc;
				}
				assert(current !is null);
			}

			lastLevel = level;
			auto addTo = current;
			if(addTo.tagName != "ol")
				addTo = addTo.parentNode;

			if(!header.hasAttribute("id"))
				header.attrs.id = toId(header.innerText);
			if(header.querySelector(" > *") is null) {
				auto selfLink = Element.make("a", header.innerText, "#" ~ header.attrs.id);
				selfLink.addClass("header-anchor");
				header.innerHTML = selfLink.toString();
			}

			addTo.addChild("li", Element.make("a", header.innerText, "#" ~ header.attrs.id));
		}

		if(auto d = document.querySelector("#more-link")) {
			if(document.querySelectorAll(".user-header").length > 2)
				d.replaceWith(toc);
		}

		skip_toc: {}

		if(auto a = document.querySelector(".annotated-prototype"))
			outer: foreach(c; a.querySelectorAll(".parameters-list")) {
				auto p = c.parentNode;
				while(p) {
					if(p.hasClass("lambda-expression"))
						continue outer;
					p = p.parentNode;
				}
				c.addClass("toplevel");
			}

		// for line numbering
		foreach(pre; document.querySelectorAll("pre.highlighted, pre.block-code[data-language!=\"\"]")) {
			addLineNumbering(pre);
		}

		import std.file;
		std.file.write(outputDirectory ~ decl.link, document.toString());
		import std.stdio;
		writeln("WRITTEN TO ", decl.link);
	}

	return document;
}

void addLineNumbering(Element pre, bool id = false) {
	if(pre.hasClass("with-line-wrappers"))
		return;
	string html;
	int count;
	foreach(idx, line; pre.innerHTML.splitLines) {
		auto num = to!string(idx + 1);
		auto href = "L"~num;
		if(id)
			html ~= "<a class=\"br\""~(id ? " id=\""~href~"\"" : "")~" href=\"#"~href~"\">"~num~" </a>";
		else
			html ~= "<span class=\"br\">"~num~" </span>";
		html ~= line;
		html ~= "\n";
		count++;
	}
	pre.innerHTML = html;
	pre.addClass("with-line-wrappers");

	if(count >= 10000)
		pre.addClass("ten-thousand-lines");
	else if(count >= 1000)
		pre.addClass("thousand-lines");
}

string lastDotOnly(string s) {
	auto idx = s.lastIndexOf(".");
	if(idx == -1) return s;
	return s[idx + 1 .. $];
}

struct InheritanceResult {
	Decl decl; // may be null
	const(BaseClass) ast;
}

abstract class Decl {
	abstract string name();
	abstract string comment();
	abstract string rawComment();
	abstract string declarationType();
	abstract const(ASTNode) getAstNode();
	abstract int lineNumber();

	abstract void getAnnotatedPrototype(MyOutputRange);
	abstract void getSimplifiedPrototype(MyOutputRange);

	DocComment parsedDocComment_;
	final @property DocComment parsedDocComment() {
		if(parsedDocComment_ is DocComment.init)
			parsedDocComment_ = parseDocumentationComment(comment, this);
		return parsedDocComment_;
	}

	void getAggregatePrototype(MyOutputRange r) {
		getSimplifiedPrototype(r);
	}

	/* virtual */ void addSupplementalData(Element) {}

	// why is this needed?!?!?!?!?
	override int opCmp(Object o) {
		return cast(int)cast(void*)this - cast(int)cast(void*)o;
	}

	Decl parentModule() {
		auto p = this;
		while(p) {
			if(p.isModule())
				return p;
			p = p.parent;
		}
		assert(0);
	}

	Decl previousSibling() {
		if(parent is null)
			return null;

		Decl prev;
		foreach(child; parent.children) {
			if(child is this)
				return prev;
			prev = child;
		}

		return null;
	}

	bool isDocumented() {
		if(comment.length) // hack
		return comment.length > 0; // cool, not a hack

		// what follows is all filthy hack
		// the C bindings in druntime are not documented, but
		// we want them to show up. So I'm gonna hack it.

		auto mod = this.parentModule.name;
		//if(mod.startsWith("core.sys") || mod.startsWith("core.stdc"))
		//	return true;
		return false;
	}

	bool isStatic() {
		foreach (a; attributes) {
			if(a.attr && a.attr.attribute.type == tok!"static")
				return true;
			// gshared also implies static (though note that shared does not!)
			if(a.attr && a.attr.attribute.type == tok!"__gshared")
				return true;
		}

		return false;
	}

	bool isPrivate() {
		IdType protection;
		foreach (a; attributes) {
			if (a.attr && isProtection(a.attr.attribute.type))
				protection = a.attr.attribute.type;
		}

		return protection == tok!"private";
	}

	// FIXME: isFinal and isVirtual
	// FIXME: it would be nice to inherit documentation from interfaces too.

	bool isProperty() {
		foreach (a; attributes) {
			if(a.attr && a.attr.atAttribute && a.attr.atAttribute.identifier.text == "property")
				return true;
		}

		return false;
	}

	bool isAggregateMember() {
		return parent ? !parent.isModule : false; // FIXME?
	}

	// does NOT look for aliased overload sets, just ones right in this scope
	// includes this in the return (plus eponymous check). Check if overloaded with .length > 1
	Decl[] getImmediateDocumentedOverloads() {
		Decl[] ret;

		if(this.parent !is null) {
			foreach(child; this.parent.children) {
				if(child.name == this.name && child.isDocumented() && !child.isPrivate())
					ret ~= child;
			}
			if(auto t = cast(TemplateDecl) this.parent)
			if(this is t.eponymousMember) {
				foreach(i; t.getImmediateDocumentedOverloads())
					if(i !is t)
						ret ~= i;
			}
		}

		return ret;
	}

	Decl[] getDittos() {
		if(this.parent is null)
			return null;

		size_t lastNonDitto;

		foreach(idx, child; this.parent.children) {
			if(!child.isDitto())
				lastNonDitto = idx;
			if(child is this) {
				break;
			}
		}

		size_t stop = lastNonDitto;
		foreach(idx, child; this.parent.children[lastNonDitto + 1 .. $])
			if(child.isDitto())
				stop = idx + lastNonDitto + 1 + 1; // one +1 is offset of begin, other is to make sure it is inclusive
			else
				break;

		return this.parent.children[lastNonDitto .. stop];
	}

	string link() {
		auto n = fullyQualifiedName();

		auto overloads = getImmediateDocumentedOverloads();
		if(overloads.length > 1) {
			int number = 1;
			foreach(overload; overloads) {
				if(overload is this)
					break;
				number++;
			}

			import std.conv : text;
			n ~= text(".", number);
		}

		n ~= ".html";
		return n;
	}

	string[] parentNameList() {
		string[] fqn = [name()];
		auto p = parent;
		while(p) {
			fqn = p.name() ~ fqn;
			p = p.parent;
		}
		return fqn;

	}

	string fullyQualifiedName() {
		string fqn = name();
		if(isModule)
			return fqn;
		auto p = parent;
		while(p) {
			fqn = p.name() ~ "." ~ fqn;
			if(p.isModule)
				break; // do NOT want package names in here
			p = p.parent;
		}
		return fqn;
	}

	InheritanceResult[] inheritsFrom() { return null; }

	// the excludeModules is meant to prevent circular lookups
	Decl lookupName(string name, bool lookUp = true, string[] excludeModules = null) {
		if(importedModules.length == 0 || importedModules[$-1].name != "object")
			addImport("object", false);

		if(name.length == 0)
			return null;
		string originalFullName = name;
		auto subject = this;
		if(name[0] == '.') {
			// global scope operator
			while(subject && !subject.isModule)
				subject = subject.parent;
			name = name[1 .. $];
			originalFullName = originalFullName[1 .. $];

		}

		auto firstDotIdx = name.indexOf(".");
		if(firstDotIdx != -1) {
			subject = subject.lookupName(name[0 .. firstDotIdx]);
			name = name[firstDotIdx + 1 .. $];
		}

		if(subject)
		while(subject) {
			foreach(child; subject.children)
				if(child.name == name)
					return child;

			if(lookUp)
			lookup: foreach(mod; subject.importedModules) {
				auto lookupInsideModule = originalFullName;
				if(auto modDeclPtr = mod.name in modulesByName) {
					auto modDecl = *modDeclPtr;

					foreach(imod; excludeModules)
						if(imod == modDeclPtr.name)
							break lookup;
					auto located = modDecl.lookupName(lookupInsideModule, mod.publicImport, excludeModules ~ this.parentModule.name);
					if(located !is null)
						return located;
				}
			}

			if(!lookUp || subject.isModule)
				subject = null;
			else
				subject = subject.parent;
		}
		else {
					// fully qualified name from this module
			subject = this;
			while(subject !is null) {
				foreach(mod; subject.importedModules) {
					if(originalFullName.startsWith(mod.name ~ ".")) {
						// fully qualified name from this module
						auto lookupInsideModule = originalFullName[mod.name.length + 1 .. $];
						if(auto modDeclPtr = mod.name in modulesByName) {
							auto modDecl = *modDeclPtr;
							auto located = modDecl.lookupName(lookupInsideModule, mod.publicImport);
							if(located !is null)
								return located;
						}
					}
				}

				if(lookUp && subject.isModule)
					subject = null;
				else
					subject = subject.parent;
			}
		}

		return null;
	}

	final Decl lookupName(const IdentifierOrTemplateInstance ic, bool lookUp = true) {
		auto subject = this;
		if(ic.templateInstance)
			return null; // FIXME

		return lookupName(ic.identifier.text, lookUp);
	}


	final Decl lookupName(const IdentifierChain ic) {
		auto subject = this;
		assert(ic.identifiers.length);

		// FIXME: leading dot?
		foreach(idx, ident; ic.identifiers) {
			subject = subject.lookupName(ident.text, idx == 0);
			if(subject is null) return null;
		}
		return subject;
	}

	final Decl lookupName(const IdentifierOrTemplateChain ic) {
		auto subject = this;
		assert(ic.identifiersOrTemplateInstances.length);

		// FIXME: leading dot?
		foreach(idx, ident; ic.identifiersOrTemplateInstances) {
			subject = subject.lookupName(ident, idx == 0);
			if(subject is null) return null;
		}
		return subject;
	}

	final Decl lookupName(const Symbol ic) {
		// FIXME dot
		return lookupName(ic.identifierOrTemplateChain);
	}


	Decl parent;
	Decl[] children;

	void writeTemplateConstraint(MyOutputRange output);

	const(VersionOrAttribute)[] attributes;

	void addChild(Decl decl) {
		decl.parent = this;
		children ~= decl;
	}

	struct ImportedModule {
		string name;
		bool publicImport;
	}
	ImportedModule[] importedModules;
	void addImport(string moduleName, bool isPublic) {
		importedModules ~= ImportedModule(moduleName, isPublic);
	}

	struct Unittest {
		const(dparse.ast.Unittest) ut;
		string code;
		string comment;
	}

	Unittest[] unittests;

	void addUnittest(const(dparse.ast.Unittest) ut, const(ubyte)[] code, string comment) {
		int slicePoint = 0;
		foreach(idx, b; code) {
			if(b == ' ' || b == '\t' || b == '\r')
				slicePoint++;
			else if(b == '\n') {
				slicePoint++;
				break;
			} else {
				slicePoint = 0;
				break;
			}
		}
		code = code[slicePoint .. $];
		unittests ~= Unittest(ut, (cast(char[]) code).idup, comment);
	}

	struct ProcessedUnittest {
		string code;
		string comment;
		bool embedded;
	}

	bool _unittestsProcessed;
	ProcessedUnittest[] _processedUnittests;

	ProcessedUnittest[] getProcessedUnittests() {
		if(_unittestsProcessed)
			return _processedUnittests;

		_unittestsProcessed = true;

		// source, comment
		ProcessedUnittest[] ret;

		Decl start = this;
		if(isDitto()) {
			foreach(child; this.parent.children) {
				if(child is this)
					break;
				if(!child.isDitto())
					start = child;
			}

		}

		bool started = false;
		if(this.parent)
		foreach(child; this.parent.children) {
			if(started) {
				if(!child.isDitto())
					break;
			} else {
				if(child is start)
					started = true;
			}

			if(started)
				foreach(test; child.unittests)
					if(test.comment.length)
						ret ~= ProcessedUnittest(test.code, test.comment);
		}
		else
			foreach(test; this.unittests)
				if(test.comment.length)
					ret ~= ProcessedUnittest(test.code, test.comment);
		_processedUnittests = ret;
		return ret;
	}

	override string toString() {
		string s;
		s ~= super.toString() ~ " " ~ this.name();
		foreach(child; children) {
			s ~= "\n";
			auto p = parent;
			while(p) {
				s ~= "\t";
				p = p.parent;
			}
			s ~= child.toString();
		}
		return s;
	}

	abstract bool isDitto();
	bool isModule() { return false; }
	bool isConstructor() { return false; }

	bool aliasThisPresent;
	Token aliasThisToken;
	string aliasThisComment;

	Decl aliasThis() {
		if(!aliasThisPresent)
			return null;
		else
			return lookupName(aliasThisToken.text, false);
	}

	DestructorDecl destructor() {
		foreach(child; children)
			if(auto dd = cast(DestructorDecl) child)
				return dd;
		return null;
	}

	PostblitDecl postblit() {
		foreach(child; children)
			if(auto dd = cast(PostblitDecl) child)
				return dd;
		return null;
	}


	abstract bool isDisabled();

	ConstructorDecl disabledDefaultConstructor() {
		foreach(child; children)
		if(child.isConstructor() && child.isDisabled()) {
			auto ctor = cast(ConstructorDecl) child;
			if(ctor.astNode.parameters || ctor.astNode.parameters.parameters.length == 0)
				return ctor;
		}
		return null;
	}
}

class ModuleDecl : Decl {
	mixin CtorFrom!Module;

	string justDocsTitle;

	override bool isModule() { return true; }

	override string declarationType() {
		return justDocsTitle ? "Article" : "module";
	}

	string packageName() {
		auto it = this.name();
		auto idx = it.lastIndexOf(".");
		if(idx == -1)
			return null;
		return it[0 .. idx];
	}
}

class AliasDecl : Decl {
	mixin CtorFrom!AliasDeclaration;

	this(const(AliasDeclaration) ad, const(VersionOrAttribute)[] attributes) {
		this.attributes = attributes;
		this.astNode = ad;
		this.initializer = null;
		// deal with the type and initializer list and storage classes
	}

	const(AliasInitializer) initializer;

	this(const(AliasDeclaration) ad, const(AliasInitializer) init, const(VersionOrAttribute)[] attributes) {
		this.attributes = attributes;
		this.astNode = ad;
		this.initializer = init;
		// deal with init
	}

	override string name() {
		if(initializer is null)
			return toText(astNode.identifierList);
		else
			return initializer.name.text;
	}

	override void getAnnotatedPrototype(MyOutputRange output) {
		void cool() {
			output.putTag("<div class=\"declaration-prototype\">");
			if(parent !is null && !parent.isModule) {
				output.putTag("<div class=\"parent-prototype\"");
				parent.getSimplifiedPrototype(output);
				output.putTag("</div><div>");
				getPrototype(output, true);
				output.putTag("</div>");
			} else {
				getPrototype(output, true);
			}
			output.putTag("</div>");
		}

		writeOverloads!cool(this, output);
	}

	override void getSimplifiedPrototype(MyOutputRange output) {
		getPrototype(output, false);
	}

	void getPrototype(MyOutputRange output, bool link) {
		// FIXME: storage classes?
		output.putTag("<span class=\"builtin-type\">alias</span> ");

		output.putTag("<span class=\"name\">");
		output.put(name);
		output.putTag("</span>");

		if(initializer && initializer.templateParameters) {
			output.putTag(toHtml(initializer.templateParameters).source);
		}

		output.put(" = ");

		if(initializer) {
			if(link)
				output.putTag(toLinkedHtml(initializer.type, this).source);
			else
				output.putTag(toHtml(initializer.type).source);
		}

		if(astNode.type) {
			if(link) {
				auto t = toText(astNode.type);
				auto decl = lookupName(t);
				if(decl is null)
					goto nulldecl;
				output.putTag(getReferenceLink(t, decl).toString);
			} else {
			nulldecl:
				output.putTag(toHtml(astNode.type).source);
			}
		}
	}
}

class VariableDecl : Decl {
	mixin CtorFrom!VariableDeclaration;

	const(Declarator) declarator;
	this(const(Declarator) declarator, const(VariableDeclaration) astNode, const(VersionOrAttribute)[] attributes) {
		this.astNode = astNode;
		this.declarator = declarator;
		this.attributes = attributes;
		this.ident = Token.init;
		this.initializer = null;
	}

	const(Token) ident;
	const(Initializer) initializer;
	this(const(VariableDeclaration) astNode, const(Token) ident, const(Initializer) initializer, const(VersionOrAttribute)[] attributes) {
		this.declarator = null;
		this.attributes = attributes;
		this.astNode = astNode;
		this.ident = ident;
		this.initializer = initializer;
	}

	override string name() {
		if(declarator)
			return declarator.name.text;
		else
			return ident.text;
	}

	override string rawComment() {
		auto it = astNode.comment ~ (declarator ? declarator.comment : astNode.autoDeclaration.comment);
		return it;
	}

	override void getAnnotatedPrototype(MyOutputRange output) {
		output.putTag("<div class=\"declaration-prototype\">");
		if(parent !is null && !parent.isModule) {
			output.putTag("<div class=\"parent-prototype\"");
			parent.getSimplifiedPrototype(output);
			output.putTag("</div><div>");
			getSimplifiedPrototypeInternal(output, true);
			output.putTag("</div>");
		} else {
			getSimplifiedPrototypeInternal(output, true);
		}
		output.putTag("</div>");
	}

	override void getSimplifiedPrototype(MyOutputRange output) {
		getSimplifiedPrototypeInternal(output, false);
	}

	final void getSimplifiedPrototypeInternal(MyOutputRange output, bool link) {
		foreach(sc; astNode.storageClasses) {
			output.putTag(toHtml(sc).source);
			output.put(" ");
		}

		if(astNode.type) {
			if(link) {
				auto html = toHtml(astNode.type).source;
				auto txt = toText(astNode.type);

				auto typeDecl = lookupName(txt);
				if(typeDecl is null || typeDecl.isPrivate || !typeDecl.isDocumented)
					goto plain;

				output.putTag("<a title=\""~typeDecl.fullyQualifiedName~"\" href=\""~typeDecl.link~"\">" ~ html ~ "</a>");
			} else {
				plain:
				output.putTag(toHtml(astNode.type).source);
			}
		} else
			output.putTag("<span class=\"builtin-type\">auto</span>");

		output.put(" ");

		output.putTag("<span class=\"name\">");
		output.put(name);
		output.putTag("</span>");

		if(declarator && declarator.templateParameters)
			output.putTag(toHtml(declarator.templateParameters).source);
	}

	override string declarationType() {
		return (isStatic() ? "static variable" : "variable");
	}
}


class FunctionDecl : Decl {
	mixin CtorFrom!FunctionDeclaration;
	override void getAnnotatedPrototype(MyOutputRange output) {
		doFunctionDec(this, output);
	}

	override Decl lookupName(string name, bool lookUp = true, string[] excludeModules = null) {
		// is it a param or template param? If so, return that.

		foreach(param; astNode.parameters.parameters) {
			if (param.name.type != tok!"")
				if(param.name.text == name) {
					return null; // it is local, but we don't have a decl..
				}
		}
		if(astNode.templateParameters && astNode.templateParameters.templateParameterList && astNode.templateParameters.templateParameterList.items)
		foreach(param; astNode.templateParameters.templateParameterList.items) {
			auto paramName = "";

			if(param.templateTypeParameter)
				paramName = param.templateTypeParameter.identifier.text;
			else if(param.templateValueParameter)
				paramName = param.templateValueParameter.identifier.text;
			else if(param.templateAliasParameter)
				paramName = param.templateAliasParameter.identifier.text;
			else if(param.templateTupleParameter)
				paramName = param.templateTupleParameter.identifier.text;

			if(paramName.length && paramName == name) {
				return null; // it is local, but we don't have a decl..
			}
		}

		if(lookUp)
			return super.lookupName(name, lookUp, excludeModules);
		else
			return null;
	}

	override string declarationType() {
		return isProperty() ? "property" : (isStatic() ? "static function" : "function");
	}

	override void getAggregatePrototype(MyOutputRange output) {
		if(isStatic()) {
			output.putTag("<span class=\"storage-class\">static</span> ");
			
		}

		getSimplifiedPrototype(output);
	}

	override void getSimplifiedPrototype(MyOutputRange output) {
		foreach(sc; astNode.storageClasses) {
			output.putTag(toHtml(sc).source);
			output.put(" ");
		}

		if(isProperty() && (paramCount == 0 || paramCount == 1 || (paramCount == 2 && !isAggregateMember))) {
			if((paramCount == 1 && isAggregateMember()) || (paramCount == 2 && !isAggregateMember())) {
				// setter
				output.putTag(toHtml(astNode.parameters.parameters[0].type).source);
				output.put(" ");
				output.putTag("<span class=\"name\">");
				output.put(name);
				output.putTag("</span>");

				output.put(" [@property setter]");
			} else {
				// getter
				putSimplfiedReturnValue(output, astNode);
				output.put(" ");
				output.putTag("<span class=\"name\">");
				output.put(name);
				output.putTag("</span>");

				output.put(" [@property getter]");
			}
		} else {
			putSimplfiedReturnValue(output, astNode);
			output.put(" ");
			output.putTag("<span class=\"name\">");
			output.put(name);
			output.putTag("</span>");
			putSimplfiedArgs(output, astNode);
		}
	}

	int paramCount() {
		return cast(int) astNode.parameters.parameters.length;
	}
}

class ConstructorDecl : Decl {
	mixin CtorFrom!Constructor;

	override void getAnnotatedPrototype(MyOutputRange output) {
		doFunctionDec(this, output);
	}

	override void getSimplifiedPrototype(MyOutputRange output) {
		output.putTag("<span class=\"lang-feature name\">");
		output.put("this");
		output.putTag("</span>");
		putSimplfiedArgs(output, astNode);
	}

	override bool isConstructor() { return true; }
}

class DestructorDecl : Decl {
	mixin CtorFrom!Destructor;

	override void getSimplifiedPrototype(MyOutputRange output) {
		output.putTag("<span class=\"lang-feature name\">");
		output.put("~this");
		output.putTag("</span>");
		output.put("()");
	}
}

class PostblitDecl : Decl {
	mixin CtorFrom!Postblit;

	override void getSimplifiedPrototype(MyOutputRange output) {
		if(isDisabled) {
			output.putTag("<span class=\"builtin-type\">");
			output.put("@disable");
			output.putTag("</span>");
			output.put(" ");
		}
		output.putTag("<span class=\"lang-feature name\">");
		output.put("this(this)");
		output.putTag("</span>");
	}
}

class MixedInTemmplateDecl : Decl {
	mixin CtorFrom!TemplateMixinExpression;

	override string declarationType() {
		return "mixin";
	}

	override void getSimplifiedPrototype(MyOutputRange output) {
		output.putTag(toHtml(astNode).source);
	}
}

class StructDecl : Decl {
	mixin CtorFrom!StructDeclaration;
	override void getAnnotatedPrototype(MyOutputRange output) {
		annotatedPrototype(this, output);
	}

}

class UnionDecl : Decl {
	mixin CtorFrom!UnionDeclaration;

	override void getAnnotatedPrototype(MyOutputRange output) {
		annotatedPrototype(this, output);
	}
}

class ClassDecl : Decl {
	mixin CtorFrom!ClassDeclaration;

	override void getAnnotatedPrototype(MyOutputRange output) {
		annotatedPrototype(this, output);
	}

	mixin InheritanceSupport;
}

class InterfaceDecl : Decl {
	mixin CtorFrom!InterfaceDeclaration;
	override void getAnnotatedPrototype(MyOutputRange output) {
		annotatedPrototype(this, output);
	}

	mixin InheritanceSupport;
}

mixin template InheritanceSupport() {
	override InheritanceResult[] inheritsFrom() {
		InheritanceResult[] ret;

		static if(is(typeof(astNode) == const(ClassDeclaration)) || is(typeof(astNode) == const(InterfaceDeclaration))) {
			if(astNode.baseClassList)
			foreach(idx, baseClass; astNode.baseClassList.items) {
				InheritanceResult ir = InheritanceResult(null, baseClass);
				if(this.parent && baseClass.type2 && baseClass.type2.symbol) {
					ir.decl = this.parent.lookupName(baseClass.type2.symbol);
				}
				ret ~= ir;
			}
		}

		return ret;
	}
}

class TemplateDecl : Decl {
	mixin CtorFrom!TemplateDeclaration;

	Decl eponymousMember() {
		foreach(child; this.children)
			if(child.name == this.name)
				return child;
		return null;
	}

	override void getAnnotatedPrototype(MyOutputRange output) {
		annotatedPrototype(this, output);
	}
}

class MixinTemplateDecl : Decl {
	mixin CtorFrom!TemplateDeclaration; // MixinTemplateDeclaration does nothing interesting except this..

	override void getAnnotatedPrototype(MyOutputRange output) {
		annotatedPrototype(this, output);
	}

	override string declarationType() {
		return "mixin template";
	}
}

class EnumDecl : Decl {
	mixin CtorFrom!EnumDeclaration;

	override void addSupplementalData(Element content) {
		doEnumDecl(this, content);
	}
}

class AnonymousEnumDecl : Decl {
	mixin CtorFrom!AnonymousEnumDeclaration;

	override string name() {
		assert(astNode.members.length > 0);
		auto name = astNode.members[0].name.text;
		return name;
	}

	override void addSupplementalData(Element content) {
		doEnumDecl(this, content);
	}

	override string declarationType() {
		return "enum";
	}
}

mixin template CtorFrom(T) {
	const(T) astNode;

	static if(!is(T == VariableDeclaration) && !is(T == AliasDeclaration))
	this(const(T) astNode, const(VersionOrAttribute)[] attributes) {
		this.astNode = astNode;
		this.attributes = attributes;
	}

	static if(is(T == Module)) {
		// this is so I can load this from the index... kinda a hack
		// it should only be used in limited circumstances
		private string _name;
		private this(string name) {
			this._name = name;
			this.astNode = null;
		}
	}

	override const(T) getAstNode() { return astNode; }
	override int lineNumber() {
		static if(__traits(compiles, astNode.name.line))
			return cast(int) astNode.name.line;
		else static if(__traits(compiles, astNode.line))
			return cast(int) astNode.line;
		else static if(__traits(compiles, astNode.declarators[0].name.line)) {
			if(astNode.declarators.length)
				return cast(int) astNode.declarators[0].name.line;
		}
		return 0;
	}

	override void writeTemplateConstraint(MyOutputRange output) {
		static if(__traits(compiles, astNode.constraint)) {
			if(astNode.constraint) {
				auto f = new MyFormatter!(typeof(output))(output);
				output.putTag("<div class=\"template-constraint\">");
				f.format(astNode.constraint);
				output.putTag("</div>");
			}
		}
	}

	override string name() {
		static if(is(T == Constructor))
			return "this";
		else static if(is(T == Destructor))
			return "~this";
		else static if(is(T == Postblit))
			return "this(this)";
		else static if(is(T == Module))
			return _name is null ? .format(astNode.moduleDeclaration.moduleName) : _name;
		else static if(is(T == AnonymousEnumDeclaration))
			{ assert(0); } // overridden above
		else static if(is(T == AliasDeclaration))
			{ assert(0); } // overridden above
		else static if(is(T == VariableDeclaration))
			{assert(0);} // not compiled, overridden above
		else static if(is(T == MixinTemplateDeclaration)) {
			return astNode.templateDeclaration.name.text;
		} else static if(is(T == StructDeclaration) || is(T == UnionDeclaration))
			if(astNode.name.text.length)
				return astNode.name.text;
			else
				return "__anonymous";
		else static if(is(T == TemplateMixinExpression)) {
			return astNode.identifier.text.length ? astNode.identifier.text : "__anonymous";
		} else
			return astNode.name.text;
	}

	override string comment() {
		static if(is(T == Module))
			return astNode.moduleDeclaration.comment;
		else {
			if(isDitto()) {
				auto ps = previousSibling;
				while(ps && ps.rawComment.length == 0)
					ps = ps.previousSibling;
				return ps ? ps.comment : rawComment();
			} else
				return rawComment();
		}
	}

	override void getAnnotatedPrototype(MyOutputRange) {}
	override void getSimplifiedPrototype(MyOutputRange output) {
		output.putTag("<span class=\"builtin-type\">");
		output.put(declarationType());
		output.putTag("</span>");
		output.put(" ");

		output.putTag("<span class=\"name\">");
		output.put(name);
		output.putTag("</span>");

		static if(__traits(compiles, astNode.templateParameters)) {
			if(astNode.templateParameters) {
				output.putTag("<span class=\"template-params\">");
				output.put(toText(astNode.templateParameters));
				output.putTag("</span>");
			}
		}
	}
	override string declarationType() {
		import std.string:toLower;
		return toLower(typeof(this).stringof[0 .. $-4]);
	}

	override bool isDitto() {
		static if(is(T == Module))
			return false;
		else {
			import std.string;
			return strip(toLower(preprocessComment(rawComment))) == "ditto";
		}
	}

	override string rawComment() {
		static if(is(T == Module))
			return astNode.moduleDeclaration.comment;
		else static if(is(T == MixinTemplateDeclaration))
			return astNode.templateDeclaration.comment;
		else
			return astNode.comment;
	}

	override bool isDisabled() {
		foreach(attribute; attributes)
			if(attribute.attr && attribute.attr.atAttribute && attribute.attr.atAttribute.identifier.text == "disable")
				return true;
		static if(__traits(compiles, astNode.memberFunctionAttributes))
		foreach(attribute; astNode.memberFunctionAttributes)
			if(attribute && attribute.atAttribute && attribute.atAttribute.identifier.text == "disable")
				return true;
		return false;
	}

}


class Looker : ASTVisitor {
	alias visit = ASTVisitor.visit;

	const(ubyte)[] fileBytes;
	string originalFileName;
	this(const(ubyte)[] fileBytes, string fileName) {
		this.fileBytes = fileBytes;
		this.originalFileName = fileName;
	}

	ModuleDecl root;


	private Decl[] stack;

	Decl previousSibling() {
		auto s = stack[$-1];
		if(s.children.length)
			return s.children[$-1];
		return s; // probably a documented unittest of the module itself
	}

	void visitInto(D, T)(const(T) t) {
		auto d = new D(t, attributes[$-1]);
		stack[$-1].addChild(d);
		stack ~= d;
		t.accept(this);
		stack = stack[0 .. $-1];
	}

	override void visit(const Module mod) {
		pushAttributes();

		root = new ModuleDecl(mod, attributes[$-1]);
		stack ~= root;
		mod.accept(this);
		assert(stack.length == 1);
	}

	override void visit(const FunctionDeclaration dec) {
		stack[$-1].addChild(new FunctionDecl(dec, attributes[$-1]));
	}
	override void visit(const Constructor dec) {
		stack[$-1].addChild(new ConstructorDecl(dec, attributes[$-1]));
	}
	override void visit(const TemplateMixinExpression dec) {
		stack[$-1].addChild(new MixedInTemmplateDecl(dec, attributes[$-1]));
	}
	override void visit(const Postblit dec) {
		stack[$-1].addChild(new PostblitDecl(dec, attributes[$-1]));
	}
	override void visit(const Destructor dec) {
		stack[$-1].addChild(new DestructorDecl(dec, attributes[$-1]));
	}

	override void visit(const StructDeclaration dec) {
		visitInto!StructDecl(dec);
	}
	override void visit(const ClassDeclaration dec) {
		visitInto!ClassDecl(dec);
	}
	override void visit(const UnionDeclaration dec) {
		visitInto!UnionDecl(dec);
	}
	override void visit(const InterfaceDeclaration dec) {
		visitInto!InterfaceDecl(dec);
	}
	override void visit(const TemplateDeclaration dec) {
		visitInto!TemplateDecl(dec);
	}
	override void visit(const MixinTemplateDeclaration dec) {
		visitInto!MixinTemplateDecl(dec.templateDeclaration);
	}
	override void visit(const EnumDeclaration dec) {
		visitInto!EnumDecl(dec);
	}
	override void visit(const AliasThisDeclaration dec) {
		stack[$-1].aliasThisPresent = true;
		stack[$-1].aliasThisToken = dec.identifier;
		stack[$-1].aliasThisComment = dec.comment;
	}
	override void visit(const AnonymousEnumDeclaration dec) {
		// we can't do anything with an empty anonymous enum, we need a name from somewhere
		if(dec.members.length)
			visitInto!AnonymousEnumDecl(dec);
	}
	override void visit(const VariableDeclaration dec) {
        	if (dec.autoDeclaration) {
			foreach (idx, ident; dec.autoDeclaration.identifiers) {
				stack[$-1].addChild(new VariableDecl(dec, ident, dec.autoDeclaration.initializers[idx], attributes[$-1]));

			}
		} else
		foreach (const Declarator d; dec.declarators) {
			stack[$-1].addChild(new VariableDecl(d, dec, attributes[$-1]));

			/*
			if (variableDeclaration.type !is null)
			{
				auto f = new MyFormatter!(typeof(app))(app);
				f.format(variableDeclaration.type);
			}
			output.putTag(app.data);
			output.put(" ");
			output.put(d.name.text);

			comment.writeDetails(output);

			writeToParentList("variable " ~ cast(string)app.data ~ " ", name, comment.synopsis, "variable");

			ascendOutOf(name);
			*/
		}
	}
	override void visit(const AliasDeclaration dec) {
		if(dec.initializers.length) { // alias a = b
			foreach(init; dec.initializers)
				stack[$-1].addChild(new AliasDecl(dec, init, attributes[$-1]));
		} else { // alias b a;
			// might include a type...
			stack[$-1].addChild(new AliasDecl(dec, attributes[$-1]));
		}
	}

	override void visit(const Unittest ut) {
		previousSibling.addUnittest(
			ut,
			fileBytes[ut.blockStatement.startLocation + 1 .. ut.blockStatement.endLocation], // trim off the opening and closing {}
			ut.comment
		);
	}

	override void visit(const ImportDeclaration id) {
		void handleSingleImport(const SingleImport si) {
			auto newName = si.rename.text;
			auto oldName = "";
			foreach(idx, ident; si.identifierChain.identifiers) {
				if(idx)
					oldName ~= ".";
				oldName ~= ident.text;
			}
			bool isPublic = false;

			foreach(a; attributes[$-1]) {
				if (a.attr && isProtection(a.attr.attribute.type))
					if(a.attr.attribute.type == tok!"public") {
						isPublic = true;
						break;
					}
			}
			stack[$-1].addImport(oldName, isPublic);
			// FIXME: handle the rest like newName
		}


		foreach(si; id.singleImports) {
			handleSingleImport(si);
		}

		if(id.importBindings && id.importBindings.singleImport)
			handleSingleImport(id.importBindings.singleImport); // FIXME: handle bindings

	}

	override void visit(const StructBody sb) {
		pushAttributes();
		sb.accept(this);
		popAttributes();
	}

	// FIXME ????
	override void visit(const VersionCondition sb) {
		attributes[$-1] ~= new VersionFakeAttribute(toText(sb.token));
		sb.accept(this);
	}

	override void visit(const BlockStatement bs) {
		pushAttributes();
		bs.accept(this);
		popAttributes();
	}

	override void visit(const ConditionalDeclaration bs) {
		pushAttributes();
		size_t previousConditions;
		if(bs.compileCondition) {
			previousConditions = attributes[$-1].length;
			bs.compileCondition.accept(this);
		}

		if(bs.trueDeclarations)
			foreach(td; bs.trueDeclarations)
				td.accept(this);

		if(bs.falseDeclaration) {
			auto slice = attributes[$-1][previousConditions .. $];
			attributes[$-1] = attributes[$-1][0 .. previousConditions];
			foreach(cond; slice)
				attributes[$-1] ~= cond.invertedClone;
			bs.falseDeclaration.accept(this);
		}
		popAttributes();
	}

	override void visit(const Declaration dec) {
		auto originalAttributes = attributes[$ - 1];
		foreach(a; dec.attributes)
			attributes[$ - 1] ~= new VersionOrAttribute(a);
		dec.accept(this);
		if (dec.attributeDeclaration is null)
			attributes[$ - 1] = originalAttributes;
	}

	override void visit(const AttributeDeclaration dec) {
		attributes[$ - 1] ~= new VersionOrAttribute(dec.attribute);
	}

	void pushAttributes() {
		attributes.length = attributes.length + 1;
	}

	void popAttributes() {
		attributes = attributes[0 .. $ - 1];
	}

	const(VersionOrAttribute)[][] attributes;
}


string format(const IdentifierChain identifierChain) {
	string r;
	foreach(count, ident; identifierChain.identifiers) {
		if (count) r ~= (".");
		r ~= (ident.text);
	}
	return r;
}

import std.algorithm : startsWith, findSplitBefore;
import std.string : strip;

//Decl[][string] packages;
ModuleDecl[string] modulesByName;

void main(string[] args) {
	import std.stdio;
	import std.path : buildPath;
	import std.getopt;

	static import std.file;
	LexerConfig config;
	StringCache stringCache = StringCache(128);

	config.stringBehavior = StringBehavior.source;
	config.whitespaceBehavior = WhitespaceBehavior.include;

	Module[] modules;
	ModuleDecl[] moduleDecls;
	ModuleDecl[] moduleDeclsGenerate;

	bool makeHtml = true;
	bool makeSearchIndex = false;

	string[] preloadArgs;

	string[] linkReferences;

	bool annotateSource = false;
	
	auto opt = getopt(args,
		std.getopt.config.passThrough,
		std.getopt.config.bundling,
		"load", "Load for automatic cross-referencing, but do not generate for it", &preloadArgs,
		"link-references", "A file defining global link references", &linkReferences,
		"skeleton|s", "Location of the skeleton file, change to your use case, Default: skeleton.html", &skeletonFile,
		"directory|o", "Output directory of the html files", &outputDirectory,
		"genHtml|h", "Generate html, default: true", &makeHtml,
		"genSource|u", "Generate annotated source", &annotateSource,
		"genSearchIndex|i", "Generate search index, default: false", &makeSearchIndex);
	
	if (outputDirectory[$-1] != '/')
		outputDirectory ~= '/';

	if (opt.helpWanted || args.length == 1) {
		defaultGetoptPrinter("A better D documentation generator\nCopyright © Adam D. Ruppe 2016-2017\n" ~
			"Syntax: " ~ args[0] ~ " /path/to/your/package\n", opt.options);
		return;
	}

	{
		import std.file;

		if(!exists(skeletonFile) && exists("skeleton-default.html"))
			copy("skeleton-default.html", skeletonFile);

		if(!exists(outputDirectory))
			mkdir(outputDirectory);
		if(!exists(outputDirectory ~ "style.css") || (timeLastModified(outputDirectory ~ "style.css") < timeLastModified("style.css")))
			copy("style.css", outputDirectory ~ "style.css");
		if(!exists(outputDirectory ~ "script.js") || (timeLastModified(outputDirectory ~ "script.js") < timeLastModified("script.js")))
			copy("script.js", outputDirectory ~ "script.js");
	}

	// FIXME: maybe a zeroth path just grepping for a module declaration in located files
	// and making a mapping of module names, package listing, and files.
	// cuz reading all of Phobos takes several seconds. Then they can parse it fully lazily.

	void process(string arg, bool generate) {
		try {
			writeln("First pass processing ", arg);
			import std.file;
			auto b = cast(ubyte[]) read(arg);

			config.fileName = arg;
			auto tokens = getTokensForParser(b, config, &stringCache);

			import std.path : baseName;
			auto m = parseModule(tokens, baseName(arg));

			auto sweet = new Looker(b, baseName(arg));
			sweet.visit(m);

			auto mod = cast(ModuleDecl) sweet.root;
			if(mod.astNode.moduleDeclaration is null)
				throw new Exception("you must have a module declaration for this to work on it");

			modules ~= m;

			if(b.startsWith(cast(ubyte[])"// just docs:"))
				sweet.root.justDocsTitle = (cast(string) b["// just docs:".length .. $].findSplitBefore(['\n'])[0].idup).strip;

			if(sweet.root.name in modulesByName)
				return; // it is here twice for some reason, do not double process

			moduleDecls ~= sweet.root;
			if(generate)
				moduleDeclsGenerate ~= sweet.root;

			assert(mod !is null);
			modulesByName[sweet.root.name] = mod;

			//packages[sweet.root.packageName] ~= sweet.root;


			if(generate && annotateSource) {
				auto annotatedSourceDocument = new Document();
				annotatedSourceDocument.parseUtf8(readText(skeletonFile), true, true);
				auto code = Element.make("pre", Html(linkUpHtml(highlight(cast(string) b), sweet.root))).addClass("d_code highlighted");
				addLineNumbering(code.requireSelector("pre"), true);
				auto content = annotatedSourceDocument.requireElementById("page-content");
				content.addChild(code);

				auto nav = annotatedSourceDocument.requireElementById("page-nav");

				void addDeclNav(Element nav, Decl decl) {
					auto li = nav.addChild("li");
					if(decl.isDocumented && !decl.isPrivate)
						li.addChild("a", "[Docs] ", "../" ~ decl.link).addClass("docs");
					li.addChild("a", decl.name, "#L" ~ to!string(decl.lineNumber == 0 ? 1 : decl.lineNumber));
					if(decl.children.length)
						nav = li.addChild("ul");
					foreach(child; decl.children)
						addDeclNav(nav, child);

				}

				auto sn = nav.addChild("div").setAttribute("id", "source-navigation");

				addDeclNav(sn.addChild("div").addClass("list-holder").addChild("ul"), mod);

				annotatedSourceDocument.title = mod.name ~ " source code";

				if(!exists(outputDirectory ~ "source"))
					mkdir(outputDirectory ~ "source");
				foreach(ele; annotatedSourceDocument.querySelectorAll("link, script[src]"))
					if(ele.tagName == "link")
						ele.attrs.href = "../" ~ ele.attrs.href;
					else
						ele.attrs.src = "../" ~ ele.attrs.src;
				std.file.write(outputDirectory ~ "source/" ~ mod.name ~ ".d.html", annotatedSourceDocument.toString());
			}


		} catch (Throwable t) {
			writeln(t.toString());
		}
	}

	args = args[1 .. $]; // remove program name

	foreach(arg; linkReferences) {
		import std.file;
		loadGlobalLinkReferences(readText(arg));
	}

	string[] generateFiles;
	foreach(argIdx, arg; args) {
		if(std.file.isDir(arg))
			foreach(string name; std.file.dirEntries(arg, "*.d", std.file.SpanMode.breadth))
				generateFiles ~= name;
		else
			generateFiles ~= arg;
	}
	args = generateFiles;


	// Process them all first so name-lookups have more chance of working
	foreach(argIdx, arg; preloadArgs) {
		if(std.file.isDir(arg)) {
			foreach(string name; std.file.dirEntries(arg, "*.d", std.file.SpanMode.breadth)) {
				bool g = false;
				foreach(idx, a; args) {
					if(a == name) {
						g = true;
						args[idx] = args[$-1];
						args = args[0 .. $-1];
						break;
					}
				}

				process(name, g);
			}
		} else {
			bool g = false;

			foreach(idx, a; args) {
				if(a == arg) {
					g = true;
					args[idx] = args[$-1];
					args = args[0 .. $-1];
					break;
				}
			}

			process(arg, g);
		}
	}

	foreach(argIdx, arg; args) {
		process(arg, true);
	}

	// create dummy packages for those not found in the source
	// this makes linking far more sane, without requiring package.d
	// everywhere (though I still strongly recommending you write them!)
		// I'm using for instead of foreach so I can append in the loop
		// and keep it going
	for(size_t i = 0; i < moduleDecls.length; i++ ) {
		auto decl = moduleDecls[i];
		auto pkg = decl.packageName;
		if(pkg is null)
			continue;
		if(pkg !in modulesByName) {
			writeln("Making FAKE package for ", pkg);
			config.fileName = "dummy";
			auto b = cast(ubyte[]) (`/++
			+/ module `~pkg~`; `);
			auto tokens = getTokensForParser(b, config, &stringCache);
			auto m = parseModule(tokens, "dummy");
			auto sweet = new Looker(b, "dummy");
			sweet.visit(m);

			auto mod = cast(ModuleDecl) sweet.root;

			moduleDecls ~= mod;
			modulesByName[pkg] = mod;

			// only generate a fake one if the real one isn't already there
			// like perhaps the real one was generated before but just not loaded
			// this time.
			if(!std.file.exists(outputDirectory ~ mod.link))
				moduleDeclsGenerate ~= mod;
		}
	}

	// add modules to their packages, if possible
	foreach(decl; moduleDecls) {
		auto pkg = decl.packageName;
		if(auto a = pkg in modulesByName) {
			(*a).addChild(decl);
		}
	}

	if(makeHtml) {
		foreach(decl; moduleDeclsGenerate) {
			if(decl.parent && moduleDeclsGenerate.canFind(decl.parent))
				continue; // it will be written in the list of children
			writeln("Generating HTML for ", decl.name);

			writeHtml(decl);
		}
	}

	if(makeSearchIndex) {

		// we need the listing and the search index
		File index;
		int id;

		static import std.file;

		// write out the landing page for JS search,
		// see the comment in the source of that html
		// for more details
		std.file.write(outputDirectory ~ "search-docs.html", import("search-docs.html"));


		// the search index is a HTML page containing some script
		// and the index XML. See the source of search-docs.js for more info.
		index = File(buildPath(outputDirectory, "search-results.html"), "wt");

		auto skeletonDocument = new Document();
		skeletonDocument.parseUtf8(std.file.readText(skeletonFile), true, true);
		auto skeletonText = skeletonDocument.toString();

		auto idx = skeletonText.indexOf("</body>");
		if(idx == -1) throw new Exception("skeleton missing body element");

		// write out the skeleton...
		index.writeln(skeletonText[0 .. idx]);

		// and then the data container for the xml
		index.writeln(`<script type="text/xml" id="search-index-container">`);

		index.writeln("<adrdox>");

		index.writeln("<listing>");
		foreach(decl; moduleDeclsGenerate) {
			writeln("Listing ", decl.name);

			writeIndexXml(decl, index, id);
		}
		index.writeln("</listing>");

		id = 0;

		// also making the search index
		foreach(decl; moduleDeclsGenerate) {
			writeln("Generating search for ", decl.name);

			generateSearchIndex(decl, id);
		}

		writeln("Writing search...");

		index.writeln("<index>");
		foreach(term, arr; searchTerms) {
			index.write("<term value=\""~xmlEntitiesEncode(term)~"\">");
			foreach(item; arr) {
				index.write("<result decl=\""~to!string(item.declId)~"\" score=\""~to!string(item.score)~"\" />");
			}
			index.writeln("</term>");
		}
		index.writeln("</index>");
		index.writeln("</adrdox>");

		// finish the container
		index.writeln("</script>");

		// write the script that runs the search
		index.writeln("<script>");
		index.write(import("search-docs.js"));
		index.writeln("</script>");

		// and close the skeleton
		index.writeln("</body></html>");
	}
}

struct SearchResult {
	int declId;
	int score;
}

string[] splitIdentifier(string name) {
	string[] ret;

	bool isUpper(dchar c) {
		return c >= 'A' && c <= 'Z';
	}

	bool breakOnNext;
	dchar lastChar;
	foreach(dchar ch; name) {
		if(ch == '_') {
			breakOnNext = true;
			continue;
		}
		if(breakOnNext || ret.length == 0 || (isUpper(ch) && !isUpper(lastChar))) {
			if(ret.length == 0 || ret[$-1].length)
				ret ~= "";
		}
		breakOnNext = false;
		ret[$-1] ~= ch;
		lastChar = ch;
	}

	return ret;
}

SearchResult[][string] searchTerms;

void generateSearchIndex(Decl decl, ref int id) {
	if(decl.isPrivate() || !decl.isDocumented())
		return;

	// this needs to match the id in index.xml!
	auto tid = ++id;

	// exact match on FQL is always a great match
	searchTerms[decl.fullyQualifiedName] ~= SearchResult(tid, 50);

	if(decl.name != "this") {
		// exact match on specific name is worth something too
		searchTerms[decl.name] ~= SearchResult(tid, 25);

		if(decl.isModule) {
			// module names like std.stdio should match stdio strongly,
			// and std is ok too. I will break them by dot and give diminsihing
			// returns.
			int score = 25;
			foreach_reverse(part; decl.name.split(".")) {
				searchTerms[part] ~= SearchResult(tid, score);
				score -= 10;
				if(score <= 0)
					break;
			}
		}

		// and so is fuzzy match
		if(decl.name != decl.name.toLower)
			searchTerms[decl.name.toLower] ~= SearchResult(tid, 15);

		// and so is partial word match
		auto splitNames = splitIdentifier(decl.name);
		if(splitNames.length) {
			foreach(name; splitNames) {
				searchTerms[name] ~= SearchResult(tid, 6);
				if(name != name.toLower)
					searchTerms[name.toLower] ~= SearchResult(tid, 3);
			}
		}
	}

	// and we want to match parent names, though worth less.
	Decl parent = decl.parent;
	while(parent !is null) {
		searchTerms[parent.name] ~= SearchResult(tid, 5);
		if(parent.name != parent.name.toLower)
			searchTerms[parent.name.toLower] ~= SearchResult(tid, 2);

		auto splitNames = splitIdentifier(parent.name);
		if(splitNames.length) {
			foreach(name; splitNames) {
				searchTerms[name] ~= SearchResult(tid, 3);
				if(name != name.toLower)
					searchTerms[name.toLower] ~= SearchResult(tid, 2);
			}
		}


		parent = parent.parent;
	}

	auto document = writeHtml(decl, false);
	assert(document !is null);

	// tags are worth a lot
	foreach(tag; document.querySelectorAll(".tag"))
		searchTerms[tag.attrs.name] ~= SearchResult(tid, to!int(tag.attrs.value.length ? tag.attrs.value : "0"));

	// and other names that are referenced are worth quite a bit.
	foreach(tag; document.querySelectorAll(".xref"))
		searchTerms[tag.innerText] ~= SearchResult(tid, tag.hasClass("parent-class") ? 10 : 5);
	foreach(tag; document.querySelectorAll("a[data-ident][title]"))
		searchTerms[tag.dataset.ident] ~= SearchResult(tid, 3);
	foreach(tag; document.querySelectorAll("a.hid[title]"))
		searchTerms[tag.innerText] ~= SearchResult(tid, 3);

	// and full-text search
	import ps = PorterStemmer;
	ps.PorterStemmer s;
	bool[const(char)[]] wordsUsed;
	foreach(tag; document.querySelectorAll(".documentation-comment")) {
		foreach(word; getWords(tag.innerText)) {
			auto w = s.stem(word.toLower);
			if(w.isIrrelevant())
				continue;
			if(w in wordsUsed)
				continue;
			wordsUsed[w] = true;
			searchTerms[s.stem(word.toLower)] ~= SearchResult(tid, 1);
		}
	}

	foreach(child; decl.children)
		generateSearchIndex(child, id);
}

bool isIrrelevant(in char[] s) {
	foreach(w; irrelevantWordList)
		if(w == s)
			return true;
	return false;
}

// These are common words in English, which I'm generally
// ignoring because they happen so often that they probably
// aren't relevant keywords
import std.meta;
alias irrelevantWordList = AliasSeq!(
    "the",
    "of",
    "and",
    "a",
    "to",
    "in",
    "is",
    "you",
    "that",
    "it",
    "he",
    "was",
    "for",
    "on",
    "are",
    "as",
    "with",
    "his",
    "they",
    "I",
    "at",
    "be",
    "this",
    "have",
    "from",
    "or",
    "one",
    "had",
    "by",
    "word",
    "but",
    "not",
    "what",
    "all",
    "were",
    "we",
    "when",
    "your",
    "can",
    "said",
    "there",
    "use",
    "an",
    "each",
    "which",
    "she",
    "do",
    "how",
    "their",
    "if",
    "will",
    "up",
    "other",
    "about",
    "out",
    "many",
    "then",
    "them",
    "these",
    "so",
    "some",
    "her",
    "would",
    "make",
    "like",
    "him",
    "into",
    "time",
    "has",
    "look",
    "two",
    "more",
    "write",
    "go",
    "see",
    "number",
    "no",
    "way",
    "could",
    "people",
    "my",
    "than",
    "first",
    "water",
    "been",
    "call",
    "who",
    "its",
    "now",
    "find",
    "long",
    "down",
    "day",
    "did",
    "get",
    "come",
    "made",
    "may",
    "part",
);

string[] getWords(string text) {
	string[] words;
	string currentWord;

	import std.uni;
	foreach(dchar ch; text) {
		if(!isAlpha(ch)) {
			if(currentWord.length)
				words ~= currentWord;
			currentWord = null;
		} else {
			currentWord ~= ch;
		}
	}

	return words;
}

import std.stdio : File;

void writeIndexXml(Decl decl, File index, ref int id) {
//import std.stdio;writeln(decl.fullyQualifiedName, " ", decl.isPrivate, " ", decl.isDocumented);
	if(decl.isPrivate() || !decl.isDocumented())
		return;

	auto cc = decl.parsedDocComment;

	// the id needs to match the search index!
	index.write("<decl id=\"" ~ to!string(++id) ~ "\" type=\""~decl.declarationType~"\">");

	index.write("<name>" ~ xmlEntitiesEncode(decl.name) ~ "</name>");
	index.write("<desc>" ~ xmlEntitiesEncode(formatDocumentationComment(cc.ddocSummary, decl)) ~ "</desc>");
	index.write("<link>" ~ xmlEntitiesEncode(decl.link) ~ "</link>");

	foreach(child; decl.children)
		writeIndexXml(child, index, id);

	index.write("</decl>");
}

string pluralize(string word, int count = 2, string pluralWord = null) {
	if(word.length == 0)
		return word;

	if(count == 1)
		return word; // it isn't actually plural

	if(pluralWord !is null)
		return pluralWord;

	switch(word[$ - 1]) {
		case 's':
		case 'a', 'i', 'o', 'u':
			return word ~ "es";
		case 'f':
			return word[0 .. $-1] ~ "ves";
		case 'y':
			return word[0 .. $-1] ~ "ies";
		default:
			return word ~ "s";
	}
}

Html toLinkedHtml(T)(const T t, Decl decl) {
	import dparse.formatter;
	string s;
	struct Foo {
		void put(in char[] a) {
			s ~= a;
		}
	}
	Foo output;
	auto f = new MyFormatter!(typeof(output))(output);
	f.format(t);

	return Html(linkUpHtml(s, decl));
}

string linkUpHtml(string s, Decl decl) {
	auto document = new Document("<root>" ~ s ~ "</root>", true, true);

	// additional cross referencing we weren't able to do at lower level
	foreach(ident; document.querySelectorAll("*:not(a) [data-ident]:not(:has(a)), .hid")) {
		// since i modify the tree in the loop, i recheck that we still match the selector
		if(ident.parentNode is null)
			continue;
		if(ident.tagName == "a" || (ident.parentNode && ident.parentNode.tagName == "a"))
			continue;
		string i = ident.hasAttribute("data-ident") ? ident.dataset.ident : ident.innerText;

		auto n = ident.nextSibling;
		while(n && n.nodeValue == ".") {
			i ~= ".";
			auto txt = n;
			n = n.nextSibling; // the span, ideally
			if(n is null)
				break;
			if(n && (n.hasAttribute("data-ident") || n.hasClass("hid"))) {
				txt.removeFromTree();
				i ~= n.hasAttribute("data-ident") ? n.dataset.ident : n.innerText;
				auto span = n;
				n = n.nextSibling;
				span.removeFromTree;
			}
		}

		//ident.dataset.ident = i;
		ident.innerText = i;

		auto found = decl.lookupName(i);
		string hash;

		if(found is null) {
			auto lastPieceIdx = i.lastIndexOf(".");
			if(lastPieceIdx != -1) {
				found = decl.lookupName(i[0 .. lastPieceIdx]);
				if(found)
					hash = "#" ~ i[lastPieceIdx + 1 .. $];
			}
		}

		if(found) {
			auto overloads = found.getImmediateDocumentedOverloads();
			if(overloads.length)
				found = overloads[0];
		}

		if(found && found.isDocumented && !found.isPrivate) {
			ident.attrs.title = found.fullyQualifiedName;
			ident.tagName = "a";
			ident.href = found.link ~ hash;
		}
	}

	return document.root.innerHTML;
}


Html toHtml(T)(const T t) {
	import dparse.formatter;
	string s;
	struct Foo {
		void put(in char[] a) {
			s ~= a;
		}
	}
	Foo output;
	auto f = new Formatter!(typeof(output))(output);
	f.format(t);

	return Html("<tt class=\"highlighted\">"~highlight(s)~"</tt>");
}

string toText(T)(const T t) {
	import dparse.formatter;
	string s;
	struct Foo {
		void put(in char[] a) {
			s ~= a;
		}
	}
	Foo output;
	auto f = new Formatter!(typeof(output))(output);
	f.format(t);

	return s;
}

string toId(string txt) {
	auto id = txt.toLower.strip.squeeze(" ").replace(" ", "-");
	return id;
}



/*
	This file contains code from https://github.com/economicmodeling/harbored/

	Those portions are Copyright 2014 Economic Modeling Specialists, Intl.,
	written by Brian Schott, made available under the following license:

	Boost Software License - Version 1.0 - August 17th, 2003

	Permission is hereby granted, free of charge, to any person or organization
	obtaining a copy of the software and accompanying documentation covered by
	this license (the "Software") to use, reproduce, display, distribute,
	execute, and transmit the Software, and to prepare derivative works of the
	Software, and to permit third-parties to whom the Software is furnished to
	do so, all subject to the following:

	The copyright notices in the Software and this entire statement, including
	the above license grant, this restriction and the following disclaimer,
	must be included in all copies of the Software, in whole or in part, and
	all derivative works of the Software, unless such copies or derivative
	works are solely in the form of machine-executable object code generated by
	a source language processor.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
	SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
	FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
	ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
	DEALINGS IN THE SOFTWARE.
*/

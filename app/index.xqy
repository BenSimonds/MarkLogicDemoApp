xquery version "1.0-ml";
declare namespace tr = "http://BIPB.com/CITES";
declare namespace pp = "http://BIPB.com/CITES/purposes";
declare namespace sr = "http://BIPB.com/CITES/sources";
declare namespace info = "http://BIPB.com/CITES/taxa";
import module namespace search = "http://marklogic.com/appservices/search" at "/MarkLogic/appservices/search/search.xqy";

declare variable $options := 
  <options xmlns="http://marklogic.com/appservices/search">
  	<term>
  	    <term-option>case-insensitive</term-option>
  	    <term-option>stemmed</term-option>
  	</term>
  	<searchable-expression>
  	    fn:collection("Trades")
  	</searchable-expression>
  	<search:operator name="sort">
  	  <search:state name="newest">
  	    <search:sort-order direction="ascending" type="xs:string">
  	      <search:element ns="http://BIPB.com/CITES" name="Taxon"/>
  	    </search:sort-order>
  		<search:sort-order>
  			<search:score/>
  		</search:sort-order>
  	</search:state>
  	</search:operator>
  </options>;

declare variable $q-text := 
	let $q := xdmp:get-request-field("q", "sort:newest")
	return $q;
declare variable $agg := 
	let $agg := xdmp:get-request-field("agg")
	return $agg;
	

declare variable $results := search:search($q-text,$options);
		

declare function local:getquantity($trades) as xs:float {
	let $max := for $trade in $trades/descendant-or-self::tr:trade
		let $importer := xs:float($trade/tr:Importer_reported_quantity/text())
  		let $exporter := xs:float($trade/tr:Exporter_reported_quantity/text())
  		let $max := fn:max(($importer, $exporter))
  		return $max
	return fn:round(fn:sum($max))
  	};

declare function local:getpurpose($trade) {
	let $code := $trade/tr:Purpose
	let $purpose := fn:doc("purposes.xml")/pp:purposes/pp:purpose[@id eq $code]/text()
	return 
	if ($purpose) then
		$purpose
	else
		"Unknown"
};

declare function local:getsource($trade) {
	let $code := $trade/tr:Source
	let $source := fn:doc("sources.xml")/sr:sources/sr:source[@id eq $code]/text()
	return 
	if ($source) then
		$source
	else
		"Unknown"
};

declare function local:getinfo($taxon) {
	let $info_uri := fn:string-join(("taxa/",$taxon,".xml"))
	let $info := fn:doc($info_uri)
	let $c_name := $info//info:common_name/text()
	return $info
};

declare function local:getimage($taxon) {
	let $uri := local:getinfo($taxon)//info:img_uri/text()
	return 
	if (fn:doc($uri))
	then <div class="pull-right"><img class="img-rounded img-species" alt="{$taxon}" src="get-file.xqy?uri={$uri}"/></div>
	else ()
};

declare function local:getinfohtml($doc) {
	let $taxon := fn:distinct-values($doc//tr:Taxon)
	let $class := fn:distinct-values($doc//tr:Class)
	let $order := fn:distinct-values($doc//tr:Order)
	let $family := fn:distinct-values($doc//tr:Family)
	let $common_name := local:getinfo($taxon)//info:common_name
	let $wikilink := local:getinfo($taxon)//info:wikilink
	let $conservation_status := local:getinfo($taxon)//info:conservation_status
	return
	<div>
		{if ($common_name eq $taxon) 
			then <h4>{$taxon}</h4>
		else if	($common_name)
			then <h4>{$common_name} ({$taxon})</h4> 
			else <h4>{$taxon}</h4>}
		{local:getimage($taxon)}
		{if ($class and $order and $family and $wikilink) 
			then  <p>Class: {$class}, Order: {$order}, Family: {$family} <br></br> <a href='{$wikilink}'>Wikipedia</a></p>
			else ()}
		{if ($conservation_status/text()) 
			then <p>Conservation Status: {$conservation_status}</p> 
			else ()}
		<p>{local:getinfo($taxon)//info:info}</p>
	</div>
};

declare function local:tradeaggr($doc) {
	let $taxon := fn:distinct-values($doc//tr:Taxon)
	let $trades := $doc//tr:trade[tr:Taxon eq $taxon]
	let $years := fn:distinct-values($trades/tr:Year)
	let $terms := fn:distinct-values(
		for $term in $trades//tr:Term
		order by fn:sum(local:getquantity($trades[tr:Term eq $term])) descending
		return $term
		)
	let $terms_restricted := $terms[1 to 5]
	let $terms_other :=
		if (fn:count($terms) < 5)
		then ()
		else $terms[6 to fn:count($terms)]
	let $terms_tr :=
		for $term in $terms_restricted
			return <th style="text-align:center">{$term}</th>
	let $details :=
		for $year in $years
			let $trades_other := $trades[tr:Term = $terms_other and tr:Year eq $year]
			let $quantity_other := local:getquantity($trades_other)
			let $quantities := 
				for $term in $terms_restricted
					let $quantity := local:getquantity($trades[tr:Year eq $year and tr:Term eq $term])
					return <td style="text-align:center">{$quantity}</td> 
			order by -$year
			return
				  <tr>
				  <td style="text-align:center">{$year}</td>
				  <td style="text-align:center">{local:getquantity($trades[tr:Year eq $year])}</td>
				  {$quantities}
				  <td style="text-align:center">{$quantity_other}</td>
				  </tr>
				    

	return <div>
		{local:getinfohtml($doc)}
		<b>Imports into the UK:</b>
		<table style="width:100%" class= "table">
			<tr>
			    <th style="text-align:center">Year</th>
			    <th style="text-align:center">Total</th>
			    {$terms_tr}
			    <th style="text-align:center">Other</th>
			</tr>
			{$details}
			</table>
			<br></br>
		</div>

};	



declare function local:tradedetails($doc) {
	let $taxa := fn:distinct-values($doc//tr:Taxon)
	let $class := fn:distinct-values($doc//tr:Class)
	let $order := fn:distinct-values($doc//tr:Order)
	let $family := fn:distinct-values($doc//tr:Family)
	(:Loop through taxa:)
	let $taxa-trades :=
		for $taxon in $taxa
		let $trades := $doc//tr:trade[tr:Taxon eq $taxon]
		let $details := 
			for $trade in $trades
			let $year := $trade/tr:Year
			let $from := $trade/tr:Exporter
			let $purpose := local:getpurpose($trade)
			let $source := local:getsource($trade)
			order by -$year
			return
				  <tr>
				    <td style="text-align:center">{$year}</td>
				    <td style="text-align:center">{local:getquantity($trade)}</td> 
				    <td>{$source}</td>
				    <td>{$purpose}</td>
				  </tr>
		return <div>
			{local:getinfohtml($doc)}
			<b>Imports into the UK:</b>
			<table style="width:100%" class= "table">
				<tr>
				    <th style="text-align:center">Year</th>
				    <th style="text-align:center">Quantity</th> 
				    <th>Source</th>
				    <th>Purpose</th>
				</tr>
				{$details}
				</table>
				<br></br>
			</div>
	return $taxa-trades			
};

declare function local:search-results() {
	let $items :=
		for $result in $results//search:result
			let $uri := fn:data($result/@uri)
			let $doc := fn:doc($uri)
			return 
			if ($agg eq "on") then
				local:tradeaggr($doc)
			else
				local:tradedetails($doc)
	return 
		if ($items)
		then ($items)
	else <div><p>Sorry, no results for your search.</p></div>
};

xdmp:set-response-content-type("text/html; charset=utf-8"),
'<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">',
<html xmlns="http://www.w3.org/1999/xhtml" lang="en">
<head>
	<meta charset="utf-8"></meta>
	<meta http-equiv="X-UA-Compatible" content="IE=edge"></meta>
	<meta name="viewport" content="width=device-width, initial-scale=1"></meta>
	<!-- The above 3 meta tags *must* come first in the head; any other head content must come *after* these tags -->
	<meta name="description" content="Test App with MarkLogic"></meta>
	<meta name="author" content="Ben Simonds"></meta>
	<link rel="icon" href="../../favicon.ico"></link>

	<title>CITES - Convention on International trade in Endangered Species of Wild Fauna and Flora</title>

	<!-- Bootstrap core CSS -->
	<link href="node_modules/bootstrap/dist/css/bootstrap.min.css" rel="stylesheet"></link>

	<!-- Custom styles for this template -->
	<link href="css/main.css" rel="stylesheet"></link>

</head>

<body>

	<nav class="navbar navbar-inverse navbar-fixed-top">
		<div class="container">
			<div class="navbar-header">
				<button type="button" class="navbar-toggle collapsed" data-toggle="collapse" data-target="#navbar" aria-expanded="false" aria-controls="navbar">
					<span class="sr-only">Toggle navigation</span>
					<span class="icon-bar"></span>
					<span class="icon-bar"></span>
					<span class="icon-bar"></span>
				</button>
				<a class="navbar-brand" href="#">CITES Imports into Great Britain</a>
			</div>
			<div id="navbar" class="collapse navbar-collapse">
				<ul class="nav navbar-nav">
					<li class="active"><a href="#">Home</a></li>
					<li><a href="#about">About</a></li>
					<li><a href="#contact">Contact</a></li>
				</ul>
			</div><!--/.nav-collapse -->
		</div>
	</nav>

	<div class="container">

		<div class="main">
			<div class="row">
				<div class="col-md-3">
					<h2>Menus And Stuff</h2>
				</div>
				<div class="col-md-9">
					<div class="row">
						<div class="col-md-9">
							<form name="form1" method="get" action="index.xqy" id="form1">
								<div class="input-group">
									<span class="input-group-addon" id="basic-addon1">Search</span>
									<input type="text" class="form-control" placeholder="Taxon, Genus, Family etc." aria-describedby="basic-addon1" name="q" id="q" value="{$q-text}"></input>
									<span class="input-group-btn">
									<button class="btn btn-default" type="submit">Go!</button>
		 							</span>
								</div>
								
								{if ($agg = "on") then
									<div class="checkbox">
									<label><input type="checkbox" name="agg" id="agg" checked="on">Aggregate Results by Year</input></label>
									</div>
								else
									<div class="checkbox">
									<label><input type="checkbox" name="agg" id="agg">Aggregate Results by Year</input></label>
									</div>
								}
								
							</form>
						</div>
					</div>
					<div class="row">
						<div class="col-md-9">
							{
								local:search-results()
							}
						</div>
					</div>
				</div>
			</div> <!--End of row-->	
		</div>
	</div><!-- /.container -->


    <!-- Bootstrap core JavaScript
    ================================================== -->
    <!-- Placed at the end of the document so the pages load faster -->
    <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.3/jquery.min.js"></script>
    <script src="../../dist/js/bootstrap.min.js"></script>
    <!-- IE10 viewport hack for Surface/desktop Windows 8 bug -->
    <script src="../../assets/js/ie10-viewport-bug-workaround.js"></script>
</body>
</html>
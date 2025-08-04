/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[SH_VendorSettingSel]
	@ProductIDs		VARCHAR(MAX) = ''
AS
/*
	Created: 20250627@Danny
	Task : Get Vendor setting (Pay to supplier)
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20250627@Danny: Initialize [Redmine: #212221]

	EXEC SH_VendorSettingSel '36,45,46,48,51,52,55,56,57,60,61,62,63,65,67,68,70,72,73,75,76,77,78,79,80,83,85,87,88,89,90,91,95,96,98,100,101,103,104,105,106,107,108,109,110'
		
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @tmp_product TABLE (ProductID INT)  

	INSERT INTO @tmp_product(ProductID)
	SELECT CAST(Value AS INT) 
	FROM   STRING_SPLIT(@ProductIDs,',')


	; WITH t AS 
	(
		SELECT l.PartyID, op.PartyName AS Groupname 
		FROM LA_f_BillingGroupSel() l
		INNER JOIN OAS_Party op WITH(NOLOCK) ON l.PartyID = op.PartyID
		UNION ALL
		SELECT 25, 'IBC (FDL)'
		UNION ALL
		SELECT 30, '18bb (PIH)'
	), tmp_thirdparty AS
	(
		SELECT PartyID FROM OAS_party WITH(NOLOCK) WHERE PartyType = 3 AND (OldRefID IS NULL OR OldRefID IN (2, 3, 5, 6))
	), d AS
	(
	SELECT	p.Productid 
			,p.ProductName 
			,CASE WHEN d.extra IS NULL THEN 'All: ' ELSE 'Others: ' END +   CAST(oc.Rate * 100 AS VARCHAR(10)) 
			+ CASE WHEN d.extra IS NOT NULL THEN CHAR(13) + d.extra  ELSE  '' END ChargeRate
			,t.PartyID AS GroupID
			,t.GroupName
			,CASE WHEN oc.ChargeType = 11 THEN 'Valid turnover' ELSE 'Gross Win' END ChargeOn
			, oc.ChargeType
			, oc.FromDate
			, oc.ToDate
			, oc.ChargeID
			, d.extra
	FROM OAS_ChargeInfo oc  WITH(NOLOCK) 
	INNER JOIN tmp_thirdparty ttp ON oc.ToParty = ttp.PartyID
	INNER JOIN t ON oc.FromParty = t.PartyID
	INNER JOIN Product3rd p WITH(NOLOCK) ON oc.ProductID = p.Productid
	INNER JOIN @tmp_product tp ON p.Productid = tp.ProductID
	OUTER APPLY 
	(
		SELECT STRING_AGG(d1.ex, CHAR(13)) as extra
		FROM 
		(
			SELECT		 STRING_AGG( e.Code + '(' + e.currency + ')',', ') + ' : '  + CAST(lcr.Rate * 100 AS VARCHAR(10))  ex
			FROM		LA_ChargeRateByCurrency lcr WITH(NOLOCK) 
			INNER JOIN	bodb02.dbo.Exchange e WITH(NOLOCK) ON lcr.CurrencyID = e.ExchangeId
			WHERE		lcr.ChargeID = oc.ChargeID
			GROUP BY	lcr.Rate
		) d1

	) d
	WHERE  oc.ChargeType IN (1 ,11)
	)

	SELECT Productid, 
		  ProductName, 
		  STRING_AGG(GroupName,', ') GroupName,
		  ChargeOn, 
		  ChargeRate,
		  FromDate, 
		  ToDate
	FROM d
	GROUP BY Productid, ProductName, ChargeOn, FromDate, ToDate, ChargeRate
	ORDER BY Productid , FromDate, ChargeRate


END
GO
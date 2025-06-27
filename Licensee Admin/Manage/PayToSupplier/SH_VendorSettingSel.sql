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
		SELECT PartyID, GroupName from LA_f_BillingGroupSel()
		UNION ALL
		SELECT 25, 'IBC (FDL)'
		UNION ALL
		SELECT 30, '18bb (PIH)'
	), tmp_thirdparty AS
	(
		SELECT PartyID FROM OAS_party WITH(NOLOCK) WHERE PartyType = 3 AND (OldRefID IS NULL OR OldRefID IN (2, 3, 5, 6))
	)
	SELECT	p.Productid 
			,p.ProductName 
			,oc.Rate
			,t.PartyID AS GroupID
			,t.GroupName
			,CASE WHEN oc.ChargeType = 11 THEN 'Valid turnover' ELSE 'Gross Win' END ChargeOn
			, oc.ChargeType
			, oc.FromDate
			, oc.ToDate
			, CASE WHEN oc.FromDate > GETDATE() THEN 1 ELSE 0 END IsAllowDelete
			, CASE WHEN GETDATE() BETWEEN oc.FromDate AND oc.ToDate THEN 1 ELSE 0 END IsAllowEdit
			, oc.ChargeID
			, d.cd
	FROM OAS_ChargeInfo oc  WITH(NOLOCK) 
	INNER JOIN tmp_thirdparty ttp ON oc.ToParty = ttp.PartyID
	INNER JOIN t ON oc.FromParty = t.PartyID
	INNER JOIN Product3rd p WITH(NOLOCK) ON oc.ProductID = p.Productid
	INNER JOIN @tmp_product tp ON p.Productid = tp.ProductID
	OUTER APPLY 
	(
		SELECT (
			SELECT		lcr.Rate, STRING_AGG( e.Code + '(' + e.currency + ')',',') as currencyList
			FROM		LA_ChargeRateByCurrency lcr WITH(NOLOCK) 
			INNER JOIN	bodb02.dbo.Exchange e WITH(NOLOCK) ON lcr.CurrencyID = e.ExchangeId
			WHERE		lcr.ChargeID = oc.ChargeID
			GROUP BY	lcr.Rate
			FOR JSON PATH
		) cd
	) d
	WHERE (p.EndOfSupportDate IS NULL OR p.EndOfSupportDate = '')
		AND oc.ChargeType IN (1 ,11)
	ORDER BY p.Productid , t.PartyID, oc.ChargeType, oc.FromDate

END
GO
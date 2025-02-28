/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20241223@Danny
	DB: DBCUST.bodb_licensee
	Description: Add setting rate On PPL Terms:
*/

USE bodb_licensee
GO
DECLARE @tmp_ChargeID TABLE (ChargeID INT)


	;WITH t AS
	(
		SELECT t.ProductID,
			1235 FromParty,
			ToParty,
			ParentChargeID,
			Rate,
			ChargeType,
			FromDate,
			ToDate,
			MinAmount,
			MaxAmount,	
			Remark	,
			BaseCurrencyId,
			FirstOfBilling,
			BasisOfBilling
		FROM OAS_ChargeInfo t WITH(NOLOCK) 
		INNER JOIN Product3rd p WITH(NOLOCK) ON t.ProductID = p.Productid
		WHERE t.FromParty = 1
		AND p.EndOfSupportDate IS  NULL
		AND GETDATE() BETWEEN t.FromDate AND t.Todate
	)
	INSERT INTO OAS_ChargeInfo (
		ProductID,
		FromParty,
		ToParty,
		ParentChargeID,
		Rate,
		ChargeType,
		FromDate,
		ToDate,
		MinAmount,
		MaxAmount,	
		Remark	,
		BaseCurrencyId,
		FirstOfBilling,
		BasisOfBilling
	)
	OUTPUT INSERTED.ChargeID  INTO @tmp_ChargeID
	SELECT ProductID,
			FromParty,
			ToParty,
			ParentChargeID,
			Rate,
			ChargeType,
			FromDate,
			ToDate,
			MinAmount,
			MaxAmount,	
			Remark	,
			BaseCurrencyId,
			FirstOfBilling,
			BasisOfBilling
	FROM t
	WHERE NOT EXISTS (
		SELECT TOP 1 1 FROM OAS_ChargeInfo u WITH(NOLOCK) 
		WHERE u.FromParty = t.FromParty
			AND u.ToParty = t.ToParty
			AND u.ProductID = t.ProductID
			AND GETDATE() BETWEEN u.FromDate AND u.Todate
	)
		 

	INSERT INTO LA_ChargeInfo_SystemMapping(ChargeID ,SystemID)
	SELECT ChargeID, 2 FROM @tmp_ChargeID 




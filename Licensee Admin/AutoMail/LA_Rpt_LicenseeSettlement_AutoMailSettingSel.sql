/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeSettlement_AutoMailSettingSel]
	@PartyId			INT
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@BaseCurrency		VARCHAR(10) OUTPUT
	,@LicenseeName		VARCHAR(50) OUTPUT
	
AS
/*  Created: 20240506@Danny
	DB: DBLIC-bodb_licensee
		
	Revisions:
		- 20240506@Danny: Create Sp  [#204167]
	
	Param's Explanation:

	DECLARE @BaseCurrency	VARCHAR(10) ,@LicenseeName	VARCHAR(50)

	EXEC  LA_Rpt_LicenseeSettlement_AutoMailSettingSel 
		@PartyId = 114,  -- 77,114, 354
		@FromDate = '2024-04-01', 
		@ToDate = '2024-04-30', 
		@BaseCurrency = @BaseCurrency OUTPUT, 
		@LicenseeName =  @LicenseeName OUTPUT

	SELECT @BaseCurrency, @LicenseeName

*/
BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE = @FromDate, @TDate DATE = @ToDate, @ProductIDs VARCHAR(4000)
	DECLARE @ColNameMapping TABLE (
		UI_Col VARCHAR(200),
		SP_Col VARCHAR(200)
	)

	INSERT INTO @ColNameMapping (UI_Col, SP_Col)
	SELECT 'Jackpot Prize', 'JackpotPrize'
	UNION ALL SELECT 'Gross Win * Charge Rate',	'LicenseeChargeRate'
	UNION ALL SELECT '<Billing Currency> equivalent', 'CompanyBase'
	UNION ALL SELECT 'Currency', 'CurrencyName'
	UNION ALL SELECT 'Promotion', 'WinningPrize'
	UNION ALL SELECT 'Odds Spread Cost', 'OddsSpreadCost'
	UNION ALL SELECT '<Licensee Name> Win Loss', 'LicenseeWL'
	UNION ALL SELECT 'Total Trans',	'Betcount'
	UNION ALL SELECT 'Company',	'Company'
	UNION ALL SELECT '<Licensee Name> Charge Rate',	'LicenseeChargeRate'
	UNION ALL SELECT 'Tips Amount',	'TipsAmount'
	UNION ALL SELECT 'Contribution', 'Contribution'
	UNION ALL SELECT 'Customer Win Loss', 'MemberWinLoss'
	UNION ALL SELECT 'Turnover', 'Turnover'
	UNION ALL SELECT 'Date', 'WinLostDate'
	UNION ALL SELECT 'Company (Gross)',	'GrossCompany'
	UNION ALL SELECT 'Tips Amount Due',	'TipsAmountDue'

	-- Get Licensee Name And Base Currency

	SELECT @BaseCurrency = e.Code,
		  @LicenseeName = p.PartyName
	FROM dbo.OAS_PartyBaseCurrency op WITH(NOLOCK)
	INNER JOIN bodb02.dbo.Exchange e  WITH(NOLOCK) ON op.BaseCurrencyId = e.ExchangeId
	INNER JOIN dbo.OAS_party p WITH(NOLOCK) ON p.PartyId = op.PartyID
	WHERE op.FromDate <= @TDate AND op.ToDate >= @FDate
		  AND op.PartyId = @PartyId

	-- Get Product list
	; WITH t AS 
	(
		SELECT DISTINCT ProductID  ProductID
		FROM	dbo.LA_InvoiceSetting  WITH(NOLOCK)
		WHERE	FromPartyID = @PartyId AND ProductID IS NOT NULL AND ToPartyId <> 221 --Testing Biller
	)
	SELECT @ProductIDs =  STRING_AGG(CAST (p.Productid AS VARCHAR(20)), ',')
	FROM (
			SELECT p3.Productid FROM Product3rd p3 WITH(NOLOCK) WHERE p3.EndOfSupportDate IS NULL
			UNION ALL
			SELECT 0 -- SB
		) p
	INNER JOIN OAS_ChargeInfo oc WITH(NOLOCK) ON oc.FromParty = @PartyId AND oc.ProductID = p.Productid AND oc.FromDate <= @TDate AND oc.ToDate >= @FDate AND oc.ChargeType = 1
	LEFT JOIN t ON p.Productid = t.ProductID
	WHERE t.ProductID IS NULL

	; WITH t AS
	(
		SELECT DISTINCT ProductID, ProductPrefix AS ProductCode, ProductName FROM LA_f_LicenseeSettlement_FigureSetting(@ProductIDs)
	)
	SELECT t.ProductID, t.ProductCode, t.ProductName, oc.FirstOfBilling, REPLACE(oc.BasisOfBilling,CHAR(10),'|') BasisOfBilling, ISNULL(gmf.MinimumFeeTerm,lm.MinFeeTerm) AS MinimumFees ,x.col_info
	FROM t 
	CROSS APPLY ( 
		SELECT 
		(
			SELECT d.Col, d.Group_, c.SP_Col FROM LA_f_LicenseeSettlement_FigureSetting(@ProductIDs) d
			LEFT JOIN @ColNameMapping c ON d.Col = c.UI_Col
			WHERE d.ProductID = t.ProductID 
			FOR JSON PATH, INCLUDE_NULL_VALUES    
		) col_info
	) x
	LEFT JOIN OAS_ChargeInfo oc WITH(NOLOCK) ON oc.FromParty = @PartyId
		AND oc.ProductID = t.Productid 
		AND oc.FromDate <= @TDate 
		AND oc.ToDate >= @FDate 
		AND oc.ChargeType = 1
		AND oc.ToParty IN (SELECT z.PartyID FROM dbo.LA_f_BillingGroupSel() z )
			
	OUTER APPLY 
	(
		SELECT d.MinimumFeeTerm 
		FROM dbo.LA_GroupMinFeeDetail d WITH(NOLOCK)
			INNER JOIN dbo.LA_GroupMinFeeAssignment a WITH(NOLOCK) ON a.GroupMinFeeID = d.GroupMinFeeID
		WHERE @FDate <= d.ToDate AND d.FromDate <= @TDate
			AND a.PartyID = @PartyId
			AND d.ProductID = t.ProductID
	) gmf
	LEFT JOIN LA_MinFee lm WITH(NOLOCK) ON lm.PartyId = @PartyId AND lm.ProductID = t.Productid AND lm.FromDate <= @TDate AND lm.ToDate >= @FDate AND lm.FeeTypeId = 1

END
GO
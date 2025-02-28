/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountByGrossWinSel]
AS

/*  
	 Created: 20211101@Percy
	 DB: DBLIC.bodb_licensee
	 Task: Manage Discount Group - Discount By Gross Win
	 
	 Revisions:
		- 20211101@Percy: Initialize SP [RedmineID: #162158]
		- 20220812@Danny: Fix issue get wrong chargerate [RedmineID: #166504]
		- 20201025@Danny: Support USDT as base currency [RedmineID: #177718]
		- 20221201@Danny: Discount group - Support many sportsbook charge rates [RedmineID: #169160]
		- 20231225@Danny: Integrate Jollysports group Licensees [RedmineID: #198293]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @CutOffDate DATE = dbo.LA_f_DiscountByGrossWin_CutOffDate()

	CREATE TABLE #DiscountGroup
	(
		DiscountGroupId		SMALLINT
		,DiscountGroupName	NVARCHAR(110)
		,FromDate			DATE
		,ToDate				DATE
		,CurrencyName		VARCHAR(10)
		,ProductId			INT
		,ProductList		VARCHAR(100)
		,RepPartyId			INT -- Representative
		,PayerList			VARCHAR(MAX)
		,ChargeRate			MONEY DEFAULT (0)
	)

	-- Get gerenal info
	INSERT INTO #DiscountGroup (DiscountGroupId, DiscountGroupName, FromDate, ToDate, CurrencyName, ProductId, ProductList, RepPartyId, PayerList)
	SELECT h.DiscountGroupId, h.DiscountGroupName, h.FromDate, h.ToDate, ISNULL(CASE WHEN e.Code = 'UST' THEN 'USDT' ELSE e.Code END, '') AS CurrencyName, p.ProductId, p.ProductName
		,rp.PartyId
		,STUFF((
			SELECT ', ' + ISNULL(NULLIF(pd.BrandName, ''), p.PartyName)
			FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK)
				INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON a.PartyId = p.PartyId
				LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON a.PartyId = pd.PartyId
			WHERE a.DiscountGroupId = h.DiscountGroupId
			FOR XML PATH (''), ROOT('str'), TYPE ).value('/str[1]','VARCHAR(MAX)') 
			, 1, 2, '') AS PayerList
	FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
		INNER JOIN dbo.LA_DiscountGroupProduct gp WITH (NOLOCK) ON h.DiscountGroupId = gp.DiscountGroupId
		INNER JOIN dbo.LA_f_Products3rd('') p ON gp.ProductId = p.ProductId
		LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON h.CurrencyId = e.ExchangeId
		CROSS APPLY (
			SELECT TOP 1 a.PartyId
			FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK)
			WHERE a.DiscountGroupId = h.DiscountGroupId
		) rp
	WHERE h.DiscountGroupType = 13 -- Discount group by gross win
		AND h.FromDate >= @CutOffDate

	-- Get charge rate
	UPDATE d
	SET d.ChargeRate = c.Rate
	FROM #DiscountGroup d
		INNER JOIN dbo.OAS_ChargeInfo c WITH (NOLOCK) ON d.RepPartyId = c.FromParty AND d.ProductId = c.ProductId
	WHERE c.ToParty IN (SELECT z.PartyID FROM dbo.LA_f_BillingGroupSel() z ) 
		AND c.ChargeType = 1
		AND d.FromDate <= c.ToDate AND d.ToDate >= c.FromDate

	-- Return data
	SELECT DiscountGroupId, DiscountGroupName, FromDate, ToDate, CurrencyName, ProductList, PayerList--, ChargeRate
	FROM #DiscountGroup

	-- Tier rate settings
	SELECT	d.DiscountGroupId, 
			d.FromAmount, 
			d.ToAmount, 
			d.ChargeRateAfterDiscount AS ChargeRateAfterDiscount
	FROM #DiscountGroup g
		 INNER JOIN dbo.LA_DiscountGroupDetail d WITH (NOLOCK) ON g.DiscountGroupId = d.DiscountGroupId
	ORDER BY d.DiscountGroupId, d.FromAmount

	DROP TABLE #DiscountGroup
END
GO
/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_InvoiceSel]
	@PartyIds		VARCHAR(4000),
	@FromDate		DATE,
	@ToDate			DATE,
	@Environment	VARCHAR(50) = 'DEV',
	@IsGroupByPartyId	BIT = 0
AS
/*	Header:
	Task : Generate invoice amount for licensee
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20190905@Bruce: Create Sp [#111586]
		- 20190924@Bruce: Include actual invoice, prepayment, cn/dn data and setupfee amount [#120220]
		- 20191016@Bruce: group data by code or by party id [#112229]
*/
BEGIN
	SET NOCOUNT ON

	-- get base currency
	--
	DECLARE @baseCurrencyList TABLE (CurrencyId INT, CurrencyName VARCHAR(5))
	INSERT INTO @baseCurrencyList(CurrencyId,CurrencyName)
	SELECT CurrencyId,CurrencyName FROM OPENQUERY(DBCUST, 'EXEC CustDB.dbo.LA_BaseCurrency_Sel') 

	-- get party list
	--
	DECLARE @partyList AS TABLE(PartyId INT,LicenseeCode VARCHAR(50))

	INSERT INTO @partyList(PartyId, LicenseeCode)
	SELECT d.PartyID, d.LicenseeCode
	FROM dbo.OAS_PartyDetail d WITH(NOLOCK)
	WHERE @IsGroupByPartyId = 1 OR d.LicenseeCode IS NOT NULL

	IF @PartyIds <> 'All'
	BEGIN
		DELETE @partyList WHERE PartyID NOT IN (SELECT val FROM dbo.strSplit(@PartyIds, ','))
	END

	DECLARE @N_FromDate DATE = DATEADD(MONTH, DATEDIFF(MONTH, 0, @FromDate) + 1, 0)
	DECLARE @N_ToDate DATE = DATEADD (DAY, -1, DATEADD(MONTH, 1, @N_FromDate))

	SELECT p.LicenseeCode, b.CurrencyName, r.ProductName, p.PartyId
		,SUM(CASE WHEN InvItemTypeId = 1 THEN ISNULL(Income,0) - ISNULL(Expense,0) ELSE 0 END) LicensingFee
		,SUM(CASE WHEN InvItemTypeId = 4 THEN ISNULL(Expense,0) ELSE 0 END) Discount
		,SUM(CASE WHEN InvItemTypeId = 6 THEN ISNULL(Expense,0) ELSE 0 END) Rebate
		,SUM(CASE WHEN InvItemTypeId IN (5,24,26) THEN ISNULL(Income,0) - ISNULL(Expense,0) ELSE 0 END) Prepayment
		,SUM(CASE WHEN InvItemTypeId IN (11,12,13,14,17,20) THEN ISNULL(Income,0) - ISNULL(Expense,0) ELSE 0 END) Others
		,SUM(CASE WHEN InvItemTypeId IN (3,25) THEN ISNULL(Income,0) - ISNULL(Expense,0) ELSE 0 END) AMF
		,SUM(CASE WHEN InvItemTypeId = 2 THEN ISNULL(Income,0) - ISNULL(Expense,0) ELSE 0 END) SetupFee
	INTO #result
	FROM @partyList p
	INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON p.PartyId = h.PartyId
	INNER JOIN @baseCurrencyList b ON h.CurrencyId = b.CurrencyId
	INNER JOIN dbo.LA_InvoiceStatement s WITH(NOLOCK) ON h.InvoiceHeaderId = s.InvoiceHeaderId
	LEFT JOIN dbo.LA_f_Products3rd('') r ON r.ProductID = s.ProductId
	WHERE h.StatusId = 0-- normal invoice
		AND h.Environment = @Environment
		AND (
			(h.InvoiceDate BETWEEN @FromDate AND @ToDate AND h.InvoiceType IN (1,3,7)) OR 
			(h.InvoiceDate BETWEEN @N_FromDate AND @N_ToDate AND h.InvoiceType IN (4,5))
		)
	GROUP BY p.LicenseeCode, b.CurrencyName, r.ProductName, p.PartyId

	IF @IsGroupByPartyId = 0
	BEGIN
		SELECT LicenseeCode,CurrencyName
			,SUM(LicensingFee) LicensingFee
			,SUM(Discount) Discount
			,SUM(Rebate) Rebate
			,SUM(Prepayment) Prepayment
			,SUM(Others) Others
		FROM #result
		GROUP BY LicenseeCode, CurrencyName
	END
	ELSE
	BEGIN
		SELECT PartyId,CurrencyName
			,SUM(LicensingFee) LicensingFee
			,SUM(Discount) Discount
			,SUM(Rebate) Rebate
			,SUM(Prepayment) Prepayment
			,SUM(Others) Others
		FROM #result
		GROUP BY PartyId, CurrencyName
	END

	DROP TABLE #result
END
GO

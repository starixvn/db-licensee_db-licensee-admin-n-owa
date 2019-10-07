/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_InvoiceSel]
	@PartyIds		VARCHAR(4000),
	@FromDate		DATE,
	@ToDate			DATE,
	@Environment	VARCHAR(50) = 'DEV'
AS
/*	Header:
	Task : Generate invoice amount for licensee
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20190905@Bruce: Create Sp [#111586]
		- 20190924@Bruce: Include setupfee only [#120220]
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
	DECLARE @partyList AS TABLE(
		PartyId			INT,
		LicenseeCode	VARCHAR(50),
		CurrencyName	VARCHAR(5)
	)
	INSERT INTO @partyList(PartyId, LicenseeCode, CurrencyName)
	SELECT d.PartyID, d.LicenseeCode, b.CurrencyName
	FROM dbo.OAS_PartyDetail d WITH(NOLOCK)
	INNER JOIN @baseCurrencyList b ON d.BaseCurrencyId = b.CurrencyId
	WHERE d.PartyID IN(SELECT val FROM dbo.strSplit(@PartyIds, ',')) AND d.LicenseeCode IS NOT NULL

	DECLARE @N_FromDate DATE = DATEADD(MONTH, DATEDIFF(MONTH, 0, @FromDate) + 1, 0)
	DECLARE @N_ToDate DATE = DATEADD (DAY, -1, DATEADD(MONTH, 1, @N_FromDate))

	SELECT p.LicenseeCode, b.CurrencyName, r.ProductName
		,SUM(CASE WHEN InvItemTypeId = 1 THEN ISNULL(Income,0) ELSE 0 END) LicensingFee
		,SUM(CASE WHEN InvItemTypeId = 4 THEN ISNULL(Expense,0) ELSE 0 END) Discount
		,SUM(CASE WHEN InvItemTypeId = 6 THEN ISNULL(Expense,0) ELSE 0 END) Rebate
		,SUM(CASE WHEN InvItemTypeId IN (5,24,26) THEN ISNULL(Expense,0) ELSE 0 END) Prepayment
		,SUM(CASE WHEN InvItemTypeId IN (11,12,13,14,17,20) THEN ISNULL(Income,0) - ISNULL(Expense,0) ELSE 0 END) Others
	INTO #result
	FROM @partyList p
	INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON p.PartyId = h.PartyId
	INNER JOIN @baseCurrencyList b ON h.CurrencyId = b.CurrencyId
	INNER JOIN dbo.LA_InvoiceStatement s WITH(NOLOCK) ON h.InvoiceHeaderId = s.InvoiceHeaderId
	INNER JOIN dbo.LA_f_Products3rd('') r ON r.ProductID = s.ProductId
	WHERE h.StatusId = 0-- normal invoice
		AND h.Environment = @Environment
		AND (
			(h.InvoiceDate BETWEEN @FromDate AND @ToDate AND h.InvoiceType IN (1,3)) OR 
			(h.InvoiceDate BETWEEN @N_FromDate AND @N_ToDate AND h.InvoiceType IN (4,5))
		)
	GROUP BY p.LicenseeCode, b.CurrencyName, r.ProductName
	
	SELECT LicenseeCode
		,SUM(LicensingFee) LicensingFee
		,SUM(Discount) Discount
		,SUM(Rebate) Rebate
		,SUM(Prepayment) Prepayment
		,SUM(Others) Others
	FROM #result
	GROUP BY LicenseeCode

	DROP TABLE #result
END
GO
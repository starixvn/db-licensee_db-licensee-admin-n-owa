/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_InvoiceSel]
	@PartyIds		VARCHAR(4000),
	@ReportMonth	DATETIME,
	@Environment	VARCHAR(50) = 'DEV'
AS
/*	Header:
	Task : Generate invoice amount for licensee
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20190905@Bruce: Create Sp [#111586]
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @FromDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @ReportMonth), 0)
	DECLARE @ToDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @ReportMonth) + 1, 0))

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

	DECLARE @AmountTypeSoftwareFee INT = 1
	DECLARE @AmountTypeSetupFee INT = 7
	DECLARE @AMF INT = 3
	DECLARE @AGP INT = 25

	-- get statement
	DECLARE @statement TABLE(Amount MONEY,Prepayment MONEY,PartyId INT)

	INSERT INTO @statement(PartyId, Amount, Prepayment)
	SELECT p.PartyId, h.Amount, SUM(ISNULL(s.Income,0) - ISNULL(s.Expense,0))
	FROM @partyList p
	INNER JOIN bodb_licensee.dbo.LA_InvoiceHeader h WITH(NOLOCK) ON p.PartyId = h.PartyId
	INNER JOIN bodb_licensee.dbo.LA_InvoiceStatement s WITH(NOLOCK) ON h.InvoiceHeaderId = s.InvoiceHeaderId
	WHERE h.StatusId = 0-- normal invoice
		AND h.Environment = @Environment
		AND h.InvoiceDate BETWEEN @FromDate AND @ToDate
		AND h.InvoiceType IN (@AmountTypeSoftwareFee,@AmountTypeSetupFee)
		AND s.InvItemTypeId IN (@AMF,@AGP)
	GROUP BY p.PartyId, h.InvoiceHeaderId, h.Amount

	SELECT p.LicenseeCode, p.CurrencyName
		, SUM(s.Amount - s.Prepayment) LicensingFee
		, SUM(s.Prepayment) Prepayment
	FROM @partyList p
	INNER JOIN @statement s ON p.PartyId = s.PartyId
	GROUP BY p.LicenseeCode, p.CurrencyName
END
GO
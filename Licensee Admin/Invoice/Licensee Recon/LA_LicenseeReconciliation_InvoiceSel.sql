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

	-- get statement
	SELECT p.LicenseeCode, b.CurrencyName
		, SUM(CASE WHEN s.InvItemTypeId = 2  THEN ISNULL(s.Income,0) - ISNULL(s.Expense,0) ELSE 0 END) LicensingFee
		, SUM(CASE WHEN s.InvItemTypeId <> 2 THEN ISNULL(s.Income,0) - ISNULL(s.Expense,0) ELSE 0 END) Prepayment
	FROM @partyList p
	INNER JOIN bodb_licensee.dbo.LA_InvoiceHeader h WITH(NOLOCK) ON p.PartyId = h.PartyId
	INNER JOIN bodb_licensee.dbo.LA_InvoiceStatement s WITH(NOLOCK) ON h.InvoiceHeaderId = s.InvoiceHeaderId
	INNER JOIN @baseCurrencyList b ON h.CurrencyId = b.CurrencyId
	WHERE h.StatusId = 0-- normal invoice
		AND h.Environment = @Environment
		AND h.InvoiceDate BETWEEN @FromDate AND @ToDate
		AND h.InvoiceType = 7 -- setup fee
		AND s.InvItemTypeId IN (2,3,25)
		-- 2 setupfee amount
		-- 3 amf amount
		-- 25 AG prepayment
	GROUP BY p.LicenseeCode, b.CurrencyName
END
GO
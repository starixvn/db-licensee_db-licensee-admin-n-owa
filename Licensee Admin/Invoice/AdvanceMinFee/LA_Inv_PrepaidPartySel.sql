/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_PrepaidPartySel]
	@UserId			INT,
	@FunctionKey	NVARCHAR(100),
	@Environment	VARCHAR(50)
AS
/*	Header:
	Created: 20171226 - Bruce.Bui
	Task : Manage AMF
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20171226@Bruce: create SP
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20190122@Parsons: Improve AG prepayment and discount setting [#104620]
		- 20190821@Parsons: Improve the ability to maintain systems [#118627]
		- 20220418@Percy: Add Credit note for AMF [RedmineID: #164139]
		- 20221109@Malcolm: add LicenseeCode, BaseCurrencyId [RedmineID : 175860]
		- 20240520@Danny: support closed status invoice [RedmineID: #194603]
		- 20250403@Eddie: More Info "PlatformId" [RedmineID: #217740]
		- 20250506@Danny: update ExchangeID data Type [RedmineID: #221242]

*/
BEGIN
	SET NOCOUNT ON

	DECLARE @InvoiceItemTypes TABLE([Key] VARCHAR(50), [Value] INT)
	DECLARE @AdvanceMinFee VARCHAR(50) = 'AdvanceMinFee', @Prepayment VARCHAR(50) = 'Prepayment', @AGPrepayment VARCHAR(50) = 'AGPrepayment'

	DECLARE @Parties TABLE(PartyId INT, PartyName VARCHAR(50), BrandName VARCHAR(50), ParentId INT, LicenseeCode VARCHAR(50), BaseCurrencyId INT, PlatformId TINYINT)
	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel @UserId = @UserId, @FunctionKey=@FunctionKey

	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId, LicenseeCode , BaseCurrencyId, PlatformId)
	EXEC dbo.LA_PartyListNonOfficialSel

	INSERT INTO @InvoiceItemTypes ([Key], [Value])
	SELECT @AdvanceMinFee, value
		FROM (VALUES(3), (5), (7), (21), (46)) AS T1(value)
	UNION ALL
	SELECT @Prepayment, value
		FROM (VALUES(22), (23), (24)) AS T2(value)
	UNION ALL
	SELECT @AGPrepayment, value
		FROM (VALUES(25), (26), (27)) AS T3(value)

	;WITH a AS (
		SELECT p.PartyId, p.PartyName, p.BrandName, p.ParentId
			, SUM(CASE WHEN invT.[Key] = @AdvanceMinFee THEN ISNULL(Income,0)-ISNULL(s.Expense,0) ELSE 0 END) AS AdvanceMinFee
			, SUM(CASE WHEN invT.[Key] = @Prepayment THEN ISNULL(Income,0)-ISNULL(s.Expense,0) ELSE 0 END) AS Prepayment
			, SUM(CASE WHEN invT.[Key] = @AGPrepayment THEN ISNULL(Income,0)-ISNULL(s.Expense,0) ELSE 0 END) AS AGBalance
		FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
		INNER JOIN @Parties p ON p.PartyId = s.RefPartyId
		INNER JOIN @InvoiceItemTypes invT ON s.InvItemTypeId = invT.Value
		WHERE h.Environment = @Environment
			AND ISNULL(h.StatusId, 0) <> -1 -- 0: normal invoice. 1: Closed
		GROUP BY p.PartyId, p.PartyName, p.BrandName, p.ParentId
	)
	SELECT DISTINCT p.PartyId, p.PartyName, p.BrandName, p.ParentId,CAST(0 AS MONEY) AS AdvanceMinFee,CAST(0 AS MONEY) AS Prepayment, CAST(0 AS MONEY) AS AGBalance
	FROM @Parties p
	INNER JOIN a ON p.PartyId = a.ParentId AND p.ParentId=0
	WHERE a.AdvanceMinFee>0 OR a.Prepayment>0 OR a.AGBalance > 0
	UNION ALL
	SELECT a.PartyId, a.PartyName, a.BrandName, a.ParentId, a.AdvanceMinFee, a.Prepayment, a.AGBalance
	FROM a
	WHERE a.AdvanceMinFee>0 OR a.Prepayment>0 OR a.AGBalance > 0
END
GO
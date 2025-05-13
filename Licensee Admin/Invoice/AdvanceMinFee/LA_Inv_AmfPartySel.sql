/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Inv_AmfPartySel]
	@HasAmf			BIT,
	@UserId			INT,
	@FunctionKey	NVARCHAR(100),
	@Environment	VARCHAR(50)
AS
/*	Header:
	Created: 20171226 - Bruce.Bui
	Task : Manage AMF
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20171226: create SP
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20190821@Parsons: Improve the ability to maintain systems [#118627]
		- 20221109@Malcolm: add LicenseeCode, BaseCurrencyId [RedmineID : 175860]
		- 20240520@Danny: support closed status invoice [RedmineID: #194603]
		- 20250403@Eddie: More Info "PlatformId" [RedmineID: #217740]
		- 20250506@Danny: update ExchangeID data Type [RedmineID: #221242]

*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Parties TABLE(PartyId INT, PartyName VARCHAR(50), BrandName VARCHAR(50), ParentId INT, HasAmf BIT,LicenseeCode VARCHAR(50), BaseCurrencyId INT, PlatformId TINYINT)
	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel @UserId = @UserId, @FunctionKey=@FunctionKey

	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId, LicenseeCode , BaseCurrencyId, PlatformId)
	EXEC dbo.LA_PartyListNonOfficialSel

	UPDATE p SET HasAmf = 1
	FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
	INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON h.InvoiceHeaderId=s.InvoiceHeaderId
	INNER JOIN @Parties p ON p.PartyId = s.RefPartyId
	WHERE s.InvItemTypeId = 3 AND p.ParentId > 0
		AND h.StatusId <> -1 -- void
		AND h.Environment=@Environment

	;WITH p AS (
		SELECT  PartyId, PartyName, BrandName, ParentId
		FROM @Parties
		WHERE ParentId>0 AND ISNULL(HasAmf,0) = @HasAmf
	)
	SELECT PartyId, PartyName, BrandName, ParentId
	FROM @Parties pp
	WHERE pp.ParentId=0 AND pp.PartyId IN (SELECT DISTINCT p.ParentId FROM p)
	UNION ALL
	SELECT PartyId, PartyName, BrandName, ParentId FROM p
END
GO
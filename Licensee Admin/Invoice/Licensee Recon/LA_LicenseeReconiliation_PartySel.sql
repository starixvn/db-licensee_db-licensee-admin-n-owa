/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconiliation_PartySel](
	@UserId			INT = 0,
	@FunctionKey	NVARCHAR(100) = ''
)
AS
/*	Header:
	Task : Get list of licensee for Reconciliation report
	DB: DBCUST.bodb_Licensee
   
	Revisions: 
		- 20190723@Bruce: Create Sp [#111586]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @functionId INT = (SELECT TOP 1 FunctionID FROM dbo.LA_Function WITH(NOLOCK) WHERE FunctionKey = @FunctionKey)
	SET @functionId = ISNULL(@functionId, 0)

	DECLARE @partyList TABLE(
		PartyId		INT,
		PartyName	VARCHAR(50),
		BrandName	VARCHAR(50),
		ParentId	INT
	)
	INSERT INTO @partyList(PartyId,PartyName,BrandName,ParentId)
	EXEC dbo.LA_PartyListSel @UserId, @functionId

	DELETE @partyList WHERE ParentId = 0

	SELECT p.PartyId, p.PartyName, d.BaseCurrencyId
		, e.Code AS BaseCurrencyCode
		, CASE WHEN ISNULL(d.LicenseeCode,'') = '' THEN CAST(p.PartyID AS VARCHAR(10)) ELSE d.LicenseeCode END
	FROM @partyList p
	INNER JOIN dbo.OAS_Party p2 WITH(NOLOCK) ON p.PartyId=p2.PartyID
	INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyId=d.PartyID
	INNER JOIN CustDb.dbo.Exchange e WITH(NOLOCK) ON d.BaseCurrencyId=e.exchangeid
	WHERE d.IsDeposit = 1
END
GO
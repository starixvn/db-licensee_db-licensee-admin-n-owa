/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_PrepaidPartySel]
	@UserId			INT,
	@FunctionId		INT,
	@Environment	VARCHAR(50)
AS
/*	Header:
	Created: 20171226 - Bruce.Bui
	Task : Manage AMF
	DB: DB052.bodb_Licensee

	Revisions:
		- 20171226: create SP
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Parties TABLE(PartyId INT, PartyName VARCHAR(50), BrandName VARCHAR(50), ParentId INT)
	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel @UserId = @UserId, @FunctionId=@FunctionId

	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListNonOfficialSel

	;WITH a AS (
		SELECT p.PartyId, p.PartyName, p.BrandName, p.ParentId
			, SUM(CASE WHEN s.InvItemTypeId IN (3,5,7,21) THEN ISNULL(Income,0)-ISNULL(s.Expense,0) ELSE 0 END) AS AdvanceMinFee
			, SUM(CASE WHEN s.InvItemTypeId IN (22,23,24) THEN ISNULL(Income,0)-ISNULL(s.Expense,0) ELSE 0 END) AS Prepayment
		FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
		INNER JOIN @Parties p ON p.PartyId = s.RefPartyId
		WHERE h.Environment = @Environment
			AND ISNULL(h.StatusId, 0) = 0 -- 0: normal invoice
			AND s.InvItemTypeId IN (3,5,7,21,22,23,24)
		GROUP BY p.PartyId, p.PartyName, p.BrandName, p.ParentId
	)
	SELECT DISTINCT p.PartyId, p.PartyName, p.BrandName, p.ParentId,CAST(0 AS MONEY) AS AdvanceMinFee,CAST(0 AS MONEY) AS Prepayment
	FROM @Parties p
	INNER JOIN a ON p.PartyId = a.ParentId AND p.ParentId=0
	WHERE a.AdvanceMinFee>0 OR a.Prepayment>0
	UNION ALL
	SELECT a.PartyId, a.PartyName, a.BrandName, a.ParentId, a.AdvanceMinFee, a.Prepayment
	FROM a
	WHERE a.AdvanceMinFee>0 OR a.Prepayment>0
END
GO

GRANT EXECUTE ON [dbo].[LA_Inv_PrepaidPartySel] TO bodbAdminNet
GO
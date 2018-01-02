/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_RemainingAmfGet]
	@ItemTypeId		SMALLINT,
	@PartyId		INT,
	@Environment	VARCHAR(50)
AS
/*	Header:
	Created: 20171226 - Bruce.Bui
	Task : Manage AMF
	DB: DB052.bodb_Licensee

	Revisions:
		- 20171226: create SP
	Explanation:
		- @ItemTypeId: 3 - AMF, 22 - Prepayment
*/
BEGIN
	SET NOCOUNT ON

	SELECT ISNULL((
		SELECT SUM(ISNULL(Income,0)) - SUM(ISNULL(Expense,0))
		FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
		WHERE h.Environment = @Environment
			AND ISNULL(h.StatusId, 0) = 0 -- 0: normal invoice
			AND s.RefPartyId = @PartyId
			AND (
				(@ItemTypeId = 3 AND s.InvItemTypeId IN (3,5,7,21)) OR
				(@ItemTypeId = 22 AND s.InvItemTypeId IN (22,23,24))
			)
	),0) AS RemainingAmf
END
GO

GRANT EXECUTE ON [dbo].[LA_Inv_RemainingAmfGet] TO bodbAdminNet
GO

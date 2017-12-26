/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_RemainingAmfGet]
	@PartyId			INT,
	@Environment		VARCHAR(50)
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

	SELECT ISNULL((
		SELECT SUM(ISNULL(Income,0)) - SUM(ISNULL(Expense,0))
		FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
		WHERE s.InvItemTypeId IN (3,5,7)
			AND h.PartyId = @PartyId
			AND ISNULL(h.StatusId, 0) = 0 -- 0: normal invoice
			AND h.Environment = @Environment
	),0) AS RemainingAmf
END
GO

GRANT EXECUTE ON [dbo].[LA_Inv_RemainingAmfGet] TO bodbAdminNet
GO

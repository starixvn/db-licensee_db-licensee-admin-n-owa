/*<info serverAlias="DBCUST-bodb_licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE [bodb_Licensee]
GO

ALTER FUNCTION [dbo].[LA_f_GetInvoiceAmount]
(
	@RefPartyId		INT
	,@StatusId		SMALLINT
	,@Environment	VARCHAR(50)
)
RETURNS TABLE
AS

/*
	Created: 20160510@Percy
	DB: DBCUST.bodb_Licensee
	Task: Get Invoice Amount

	Revisions:
		- 20160510@Percy: Initialize SP [RedmineID: #103658]
*/

RETURN
	SELECT s.Income, s.Expense, s.InvItemTypeId
	FROM dbo.LA_InvoiceStatement s WITH(NOLOCK)
		INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON s.InvoiceHeaderId=h.InvoiceHeaderId
	WHERE s.RefPartyId = @RefPartyId
		AND ISNULL(h.StatusId, 0) = @StatusId
		AND h.Environment = @Environment
GO

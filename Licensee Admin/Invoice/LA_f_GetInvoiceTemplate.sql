/*<info serverAlias="DBCUST-bodb_licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE [bodb_Licensee]
GO

ALTER FUNCTION [dbo].[LA_f_GetInvoiceTemplate]
(
	@FromPartyId	INT
	,@ToPartyId		INT
	,@InvTypeId		SMALLINT
)
RETURNS TABLE
AS

/*
	Created: 20160510@Percy
	DB: DBCUST.bodb_Licensee
	Task: Get Invoice Template Name

	Revisions:
		- 20160510@Percy: Initialize SP [RedmineID: #103658]
*/

RETURN
	SELECT	TOP 1 t.InvTemplateName AS InvoiceTemplateName
	FROM	dbo.LA_InvoiceSetting i WITH(NOLOCK)
			INNER JOIN dbo.LA_InvoiceTemplate t WITH(NOLOCK) ON i.InvTempId = t.InvTemplateId
	WHERE	i.FromPartyId = @FromPartyId
			AND i.ToPartyId = @ToPartyId
			AND i.InvTypeId = @InvTypeId
GO
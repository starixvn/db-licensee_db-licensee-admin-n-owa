/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_InvoiceTemplateListSel]
	 @InvoiceTemplateId	INT	= 0	
AS
/*  
	 Created: 20150413@Florent
	 Task : get List template by all or id
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:
		- 20150413@Florent: Initialize SP

	 Params:
		+ 0 get all Invoice template
		+ <> 0 specify a Invoice template
	 Example:
		EXEC dbo.LA_InvoiceTemplateListSel 0
*/
BEGIN
	SET NOCOUNT ON

	SELECT InvTemplateId, InvTemplateName, TemplatePath
	FROM dbo.LA_InvoiceTemplate WITH (NOLOCK)
	WHERE (@InvoiceTemplateId = 0 OR InvTemplateId = @InvoiceTemplateId)
END
GO
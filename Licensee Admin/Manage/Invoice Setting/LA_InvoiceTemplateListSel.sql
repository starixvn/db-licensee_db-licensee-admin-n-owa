USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_InvoiceTemplateListSel]
	 @InvoiceTemplateId	INT	= 0	
AS
/*  
	 Created: 20150413@Florent
	 Task : get List template by all or id
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     		  
	 Params:
		+ 0 get all Invoice template
		+ <> 0 specify a Invoice template
	 Example:
		EXEC dbo.LA_InvoiceTemplateListSel 0
*/
SET NOCOUNT ON
BEGIN
	SELECT InvTemplateId, InvTemplateName, TemplatePath
	FROM dbo.LA_InvoiceTemplate WITH (NOLOCK)
	WHERE (@InvoiceTemplateId = 0 OR InvTemplateId = @InvoiceTemplateId)
		
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_InvoiceTemplateListSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_InvoiceTemplateListSel] TO bodbAdminNet 
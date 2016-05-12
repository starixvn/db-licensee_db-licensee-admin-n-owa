USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_InvoiceTypeListSel]
	 @InvoiceTypeId	INT	= 0	
AS
/*  
	 Created: 20150413@Florent
	 Task : get List Invoice type by all or id
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     		  
	 Params:
		+ 0 get all Invoice type
		+ <> 0 specify a Invoice type
	 Example:
		EXEC dbo.LA_InvoiceTypeListSel 0
*/
SET NOCOUNT ON
BEGIN
	SELECT InvTypeId, InvTypeName
	FROM dbo.LA_InvoiceType WITH (NOLOCK)
	WHERE (@InvoiceTypeId = 0 OR InvTypeId = @InvoiceTypeId)
		
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_InvoiceTypeListSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_InvoiceTypeListSel] TO bodbAdminNet 
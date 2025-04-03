/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_InvoiceTemplateListSel]
	@InvoiceTemplateId	INT	= 0
   ,@BillerName NVARCHAR(50) = ''
AS
/*  
	Created: 20150413@Florent
	Task : get List template by all or id
	DB: DBCUST.bodb_Licensee  
   
	Revisions:
		- 20150413@Florent: Initialize SP
		- 20250403@Eddie: Get template follow Biller [RedmineID: #217740]

	Params:
		- @InvoiceTemplateId :
			+ 0 get all Invoice template
			+ <> 0 specify a Invoice template
	Example:
		EXEC dbo.LA_InvoiceTemplateListSel 0
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @InvTemplate NVARCHAR(50) = ''
	
	SELECT @InvTemplate = CASE @BillerName WHEN N'Reasternhold Limited' THEN 'Reasternhold'
										   WHEN N'JollySports' 		   	THEN 'Jollysports'
										   WHEN N'Double S' 			THEN 'Double-S'
						  ELSE '' END

	SELECT InvTemplateId, InvTemplateName, TemplatePath
	FROM dbo.LA_InvoiceTemplate WITH (NOLOCK)
	WHERE (@InvoiceTemplateId = 0 OR InvTemplateId = @InvoiceTemplateId)
	  AND (@BillerName = '' OR InvTemplateName LIKE '%' + @InvTemplate)
END
GO
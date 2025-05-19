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
		- 20250428@Eddie: For new Biller [RedmineID: #225376]
		- 20250507@Danny: For new Internal biller [RedmineID: #222972]
		- 20250512@Eddie: Enhance SP [RedmineID: #226204]

	Params:
		- @InvoiceTemplateId :
			+ 0 get all Invoice template
			+ <> 0 specify a Invoice template
	Example:
		EXEC dbo.LA_InvoiceTemplateListSel 0
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @InvTemplate NVARCHAR(50) = '', @BillerRHL NVARCHAR(50), @BillerJS NVARCHAR(50), @BillerDSS NVARCHAR(50), @BillerFSL NVARCHAR(50), @BillerIS NVARCHAR(50)
	
	SELECT @BillerRHL = MAX(CASE WHEN BillerNameAbbreviation = 'RHL' THEN BillerName END )
	     , @BillerJS  = MAX(CASE WHEN BillerNameAbbreviation = 'JS'  THEN BillerName END )
	     , @BillerDSS = MAX(CASE WHEN BillerNameAbbreviation = 'DSS' THEN BillerName END )
	     , @BillerFSL = MAX(CASE WHEN BillerNameAbbreviation = 'FSL' THEN BillerName END )
	     , @BillerIS  = MAX(CASE WHEN BillerNameAbbreviation = 'IS'  THEN BillerName END )
	FROM dbo.LA_BillerInfo WITH (NOLOCK)
	
	
	SELECT @InvTemplate = CASE @BillerName WHEN @BillerRHL THEN 'Reasternhold'
										   WHEN @BillerJS  THEN 'Jollysports'
										   WHEN @BillerDSS THEN 'Double-S'
										   WHEN @BillerFSL THEN 'Fastlink'
										   WHEN @BillerIS  THEN 'Internal-Settlement'
						  ELSE '' END

	IF (@InvTemplate <> 'Fastlink')
	BEGIN
		SELECT InvTemplateId, InvTemplateName, TemplatePath
		FROM dbo.LA_InvoiceTemplate WITH (NOLOCK)
		WHERE (@InvoiceTemplateId = 0 OR InvTemplateId = @InvoiceTemplateId)
	      AND (@BillerName = '' OR InvTemplateName LIKE '%' + @InvTemplate)
	END
	ELSE
	BEGIN
		SELECT InvTemplateId, InvTemplateName, TemplatePath
		FROM dbo.LA_InvoiceTemplate WITH (NOLOCK)
		WHERE (@InvoiceTemplateId = 0 OR InvTemplateId = @InvoiceTemplateId)
	      AND (InvTemplateName = 'Zelianta' OR InvTemplateName LIKE '%' + @InvTemplate)
	END
END
GO
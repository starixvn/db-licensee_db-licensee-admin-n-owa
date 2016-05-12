USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_DiscountGroupValidListSel] 
	@DiscountGroupType TINYINT
AS
/*  
	 Created: 20150422@Florent
	 Task : get all valid group
	 DB: DB052.bodb_Licensee
	 Revisions:     
		
	 Params:
*/
BEGIN
	SET NOCOUNT ON
	SELECT DiscountGroupId, DiscountGroupName
	FROM dbo.LA_DiscountGroupHeader WITH(NOLOCK)
	WHERE DiscountGroupType = @DiscountGroupType
		AND CONVERT(DATE,GETDATE()) BETWEEN FromDate AND ToDate
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_DiscountGroupValidListSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_DiscountGroupValidListSel] TO bodbAdminNet
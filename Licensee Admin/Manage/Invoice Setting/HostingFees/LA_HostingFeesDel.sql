USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_HostingFeesDel]
	@HostingFeesId	INT,
	@UserID			INT,
	@LoginIP		VARCHAR (50)	= '',
	@ErrCode		INT				= 0		OUTPUT,
	@ErrMsg			NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20160615@Bravo
	 Task : Delete hosting fees settings
	 DB: DB052.bodb_Licensee  
   
	 Revisions:
	 Params:
		
	 Example:
		EXEC dbo.[LA_HostingFeesDel] 1
*/
BEGIN	
	SET NOCOUNT ON
	IF EXISTS (SELECT 1 FROM dbo.LA_HostingFeesSetting WHERE HostingFeesId = @HostingFeesId)
	BEGIN
		SELECT 	@ErrMsg = 'This setting is being used.', @ErrCode = 2	
		RETURN
	END

	DELETE FROM dbo.LA_HostingFees WHERE HostingFeesId = @HostingFeesId
	DELETE FROM dbo.LA_HostingFeesDetail WHERE HostingFeesId = @HostingFeesId
	
	-- Write Log

	--
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_HostingFeesDel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_HostingFeesDel] TO bodbAdminNet 


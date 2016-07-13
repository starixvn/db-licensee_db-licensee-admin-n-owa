USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_HostingFeesPayerSettingsDel]
	@PayerId	INT,
	@UserID		INT,
	@LoginIP	VARCHAR (50)	= '',
	@ErrCode	INT				= 0		OUTPUT,
	@ErrMsg		NVARCHAR(1000)	= ''	OUTPUT
AS
/*
	Created: 201600713@Bruce
	Task : Delete all hosting fees settings of payer
	DB: DB052.bodb_Licensee

	Revisions:
		201600708@Bruce: create
	Params:

	Example:
		EXEC dbo.LA_HostingFeesPayerSettingsDel 14
*/
BEGIN	
	SET NOCOUNT ON

	DELETE FROM dbo.LA_HostingFeesSetting WHERE FromParty = @PayerId

	-- Write Log

	--
END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_HostingFeesPayerSettingsDel] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_HostingFeesPayerSettingsDel] TO bodbAdminNet

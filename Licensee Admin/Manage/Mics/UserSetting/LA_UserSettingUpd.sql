/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_UserSettingUpd]
	@UserId			INT,
	@Id				INT				= 0,
	@Data			VARCHAR(8000),
	@FunctionKey	NVARCHAR(100),
	@ErrCode		INT				= 0		OUTPUT, 
	@ErrMsg			VARCHAR(4000)	= ''	OUTPUT
AS
/*
	Created: 20190911@Parsons
	Task : Save query filters in LPID report [#FeatureId 119536]
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190911@Parsons: add new sp

	Param's Explannation: 
*/
BEGIN
	SET NOCOUNT ON

	IF (@UserId <= 0 OR @Data = '' OR @FunctionKey = '' OR @Id <= 0) 
	BEGIN
		SELECT @ErrMsg = 'Setting is invalid, Please check again.', @ErrCode =  505
		RETURN
	END

	IF NOT EXISTS (SELECT TOP 1 1 FROM [dbo].[LA_UserSettings] WITH(NOLOCK) WHERE UserId = @UserId AND FunctionKey = @FunctionKey AND Id = @Id) 
	BEGIN
		SELECT @ErrMsg = 'User''s setting doesn''t exists.', @ErrCode =  508
		RETURN
	END

	UPDATE LA_UserSettings
	SET [Data] = @Data
	WHERE Id = @Id
END
GO